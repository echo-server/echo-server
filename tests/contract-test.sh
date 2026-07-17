#!/usr/bin/env bash

set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly image_name="${ECHO_SERVER_TEST_IMAGE:-echo-server:contract-test}"
readonly run_suffix="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$$"
readonly container_name="echo-server-contract-${run_suffix}"
temporary_directory="$(mktemp -d)"
readonly temporary_directory

container_started=false

log() {
    printf '[contract-test] %s\n' "$*"
}

fail() {
    printf '[contract-test] ERROR: %s\n' "$*" >&2
    return 1
}

cleanup() {
    local exit_status=$?

    trap - EXIT

    if [[ "${exit_status}" -ne 0 ]] && [[ "${container_started}" == true ]]; then
        printf '\n[contract-test] Container logs after failure:\n' >&2
        docker container logs "${container_name}" >&2 || true
    fi

    if docker container inspect "${container_name}" >/dev/null 2>&1; then
        docker container rm --force "${container_name}" >/dev/null
    fi

    if [[ -d "${temporary_directory}" ]]; then
        rm -r -- "${temporary_directory}"
    fi

    exit "${exit_status}"
}

trap cleanup EXIT

assert_equal() {
    local expected=$1
    local actual=$2
    local description=$3

    if [[ "${actual}" != "${expected}" ]]; then
        fail "${description}: expected '${expected}', got '${actual}'"
    fi
}

assert_file_contains() {
    local file=$1
    local expected=$2
    local description=$3

    if ! grep --fixed-strings --quiet -- "${expected}" "${file}"; then
        printf '[contract-test] File contents (%s):\n' "${file}" >&2
        sed -n '1,240p' "${file}" >&2
        fail "${description}: missing '${expected}'"
    fi
}

assert_file_matches() {
    local file=$1
    local pattern=$2
    local description=$3

    if ! grep --extended-regexp --quiet -- "${pattern}" "${file}"; then
        printf '[contract-test] File contents (%s):\n' "${file}" >&2
        sed -n '1,240p' "${file}" >&2
        fail "${description}: pattern '${pattern}' did not match"
    fi
}

worker_process_id() {
    docker container exec "${container_name}" sh -eu -c '
        master_pid=$(cat /usr/local/openresty/nginx/logs/nginx.pid)
        set -- $(cat "/proc/${master_pid}/task/${master_pid}/children")
        if [ "$#" -ne 1 ]; then
            echo "expected one worker process, found $#" >&2
            exit 1
        fi
        printf "%s\n" "$1"
    '
}

process_entry_count() {
    local process_id=$1
    local entry_type=$2

    docker container exec "${container_name}" sh -eu -c '
        set -- /proc/"$1"/"$2"/*
        printf "%s\n" "$#"
    ' sh "${process_id}" "${entry_type}"
}

assert_silent_hang() {
    local test_name=$1
    shift

    local headers_file="${temporary_directory}/${test_name}.headers"
    local body_file="${temporary_directory}/${test_name}.body"
    local stderr_file="${temporary_directory}/${test_name}.stderr"
    local curl_status=0

    : >"${headers_file}"
    : >"${body_file}"

    curl \
        --silent \
        --show-error \
        --max-time 1 \
        --dump-header "${headers_file}" \
        --output "${body_file}" \
        --stderr "${stderr_file}" \
        "$@" \
        "${base_url}/hang" || curl_status=$?

    assert_equal 28 "${curl_status}" "${test_name} curl timeout status"

    if [[ -s "${headers_file}" ]]; then
        fail "${test_name} unexpectedly received response headers"
    fi
    if [[ -s "${body_file}" ]]; then
        fail "${test_name} unexpectedly received a response body"
    fi

    log "${test_name}: timed out with zero response bytes"
}

for required_command in curl docker grep sed; do
    if ! command -v "${required_command}" >/dev/null 2>&1; then
        fail "required command is unavailable: ${required_command}"
    fi
done

if ! curl --version | grep --quiet 'HTTP2'; then
    fail 'curl does not include HTTP/2 support'
fi

log "Building native test image ${image_name}"
docker build --pull --tag "${image_name}" "${repository_root}"

log 'Validating OpenResty configuration'
docker run --rm "${image_name}" openresty -t

log 'Starting test container'
docker run \
    --detach \
    --name "${container_name}" \
    --publish 127.0.0.1::80 \
    "${image_name}" >/dev/null
container_started=true

mapped_port=''
for _ in {1..30}; do
    mapped_port="$(docker container port "${container_name}" 80/tcp 2>/dev/null | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | sed -n '1p' || true)"
    if [[ -n "${mapped_port}" ]]; then
        break
    fi
    sleep 0.1
done

if [[ -z "${mapped_port}" ]]; then
    fail 'could not determine the published HTTP port'
fi

readonly base_url="http://127.0.0.1:${mapped_port}"

ready=false
for _ in {1..50}; do
    if curl --http1.1 --fail --silent --max-time 1 --output /dev/null "${base_url}/"; then
        ready=true
        break
    fi
    sleep 0.1
done

if [[ "${ready}" != true ]]; then
    fail 'container did not become ready'
fi

log "Container is ready at ${base_url}"

get_headers="${temporary_directory}/get.headers"
get_body="${temporary_directory}/get.body"
get_status="$(curl \
    --http1.1 \
    --silent \
    --show-error \
    --header 'Host: contract.example' \
    --header 'X-Contract-Test: header-value' \
    --dump-header "${get_headers}" \
    --output "${get_body}" \
    --write-out '%{http_code}' \
    "${base_url}/contract?case=get")"

assert_equal 200 "${get_status}" 'HTTP/1.1 GET status'
if ! tr -d '\r' <"${get_headers}" | grep --ignore-case --quiet '^server: echoserver$'; then
    fail 'HTTP/1.1 GET response is missing Server: echoserver'
fi
assert_file_contains "${get_body}" 'method=GET' 'HTTP/1.1 GET method echo'
assert_file_contains "${get_body}" 'real_path=/contract?case=get' 'HTTP/1.1 GET path echo'
assert_file_contains "${get_body}" 'query=case=get' 'HTTP/1.1 GET query echo'
assert_file_contains "${get_body}" 'request_version=1.1' 'HTTP/1.1 protocol echo'
assert_file_contains "${get_body}" 'host=contract.example' 'HTTP/1.1 Host echo'
assert_file_contains "${get_body}" 'x-contract-test=header-value' 'HTTP/1.1 custom header echo'
log 'HTTP/1.1 GET contract passed'

post_body="${temporary_directory}/post.body"
post_status="$(curl \
    --http1.1 \
    --silent \
    --show-error \
    --request POST \
    --header 'Content-Type: text/plain' \
    --data-binary 'contract request body' \
    --output "${post_body}" \
    --write-out '%{http_code}' \
    "${base_url}/submit?case=post")"

assert_equal 200 "${post_status}" 'HTTP/1.1 POST status'
assert_file_contains "${post_body}" 'method=POST' 'HTTP/1.1 POST method echo'
assert_file_contains "${post_body}" 'real_path=/submit?case=post' 'HTTP/1.1 POST path echo'
assert_file_contains "${post_body}" 'contract request body' 'HTTP/1.1 POST body echo'
log 'HTTP/1.1 POST contract passed'

http2_body="${temporary_directory}/http2.body"
http2_status="$(curl \
    --http2-prior-knowledge \
    --silent \
    --show-error \
    --output "${http2_body}" \
    --write-out '%{http_code}' \
    "${base_url}/contract?case=http2")"

assert_equal 200 "${http2_status}" 'HTTP/2 GET status'
assert_file_matches "${http2_body}" 'request_version=2(\.0)?$' 'HTTP/2 protocol echo'
log 'HTTP/2 GET contract passed'

empty_port_host_body="${temporary_directory}/empty-port-host.body"
empty_port_host_status="$(curl \
    --http1.1 \
    --silent \
    --show-error \
    --header 'Host: contract.example:' \
    --output "${empty_port_host_body}" \
    --write-out '%{http_code}' \
    "${base_url}/contract?case=empty-port-host")"

assert_equal 200 "${empty_port_host_status}" 'empty-port Host compatibility status'
assert_file_contains "${empty_port_host_body}" 'host=contract.example:' 'empty-port Host compatibility echo'
log 'Empty-port Host compatibility contract passed'

invalid_port_host_status="$(curl \
    --http1.1 \
    --silent \
    --show-error \
    --header 'Host: contract.example:80a' \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${base_url}/contract?case=invalid-port-host")"

assert_equal 400 "${invalid_port_host_status}" 'invalid-port Host rejection status'
log 'Invalid-port Host rejection contract passed'

assert_silent_hang hang-http1 --http1.1
assert_silent_hang hang-http2 --http2-prior-knowledge
assert_silent_hang hang-post --http1.1 --request POST --data-binary 'discard this request body'

sleep 0.2
worker_pid="$(worker_process_id)"
baseline_fd_count="$(process_entry_count "${worker_pid}" fd)"
baseline_thread_count="$(process_entry_count "${worker_pid}" task)"
readonly worker_pid baseline_fd_count baseline_thread_count

log "Worker ${worker_pid} baseline: ${baseline_fd_count} FDs, ${baseline_thread_count} threads"

readonly concurrent_hang_count=6
declare -a hang_process_ids=()

for ((index = 1; index <= concurrent_hang_count; index++)); do
    curl \
        --http1.1 \
        --silent \
        --show-error \
        --max-time 3 \
        --dump-header "${temporary_directory}/concurrent-${index}.headers" \
        --output "${temporary_directory}/concurrent-${index}.body" \
        --stderr "${temporary_directory}/concurrent-${index}.stderr" \
        "${base_url}/hang" &
    hang_process_ids+=("$!")
done

expected_active_fd_count=$((baseline_fd_count + concurrent_hang_count))
active_fd_count=0
for _ in {1..30}; do
    active_fd_count="$(process_entry_count "${worker_pid}" fd)"
    if ((active_fd_count >= expected_active_fd_count)); then
        break
    fi
    sleep 0.1
done

if ((active_fd_count < expected_active_fd_count)); then
    fail "worker did not retain all concurrent hangs: expected at least ${expected_active_fd_count} FDs, got ${active_fd_count}"
fi

active_thread_count="$(process_entry_count "${worker_pid}" task)"
assert_equal "${baseline_thread_count}" "${active_thread_count}" 'worker thread count while requests hang'
log "Concurrent hangs retained sockets without adding worker threads (${active_fd_count} FDs)"

for ((index = 0; index < concurrent_hang_count; index++)); do
    curl_status=0
    wait "${hang_process_ids[index]}" || curl_status=$?
    assert_equal 28 "${curl_status}" "concurrent hang $((index + 1)) curl timeout status"

    if [[ -s "${temporary_directory}/concurrent-$((index + 1)).headers" ]]; then
        fail "concurrent hang $((index + 1)) unexpectedly received response headers"
    fi
    if [[ -s "${temporary_directory}/concurrent-$((index + 1)).body" ]]; then
        fail "concurrent hang $((index + 1)) unexpectedly received a response body"
    fi
done

final_fd_count="$(process_entry_count "${worker_pid}" fd)"
for _ in {1..50}; do
    final_fd_count="$(process_entry_count "${worker_pid}" fd)"
    if ((final_fd_count <= baseline_fd_count)); then
        break
    fi
    sleep 0.1
done

if ((final_fd_count > baseline_fd_count)); then
    fail "worker FDs did not return to baseline after client aborts: baseline ${baseline_fd_count}, final ${final_fd_count}"
fi

final_thread_count="$(process_entry_count "${worker_pid}" task)"
assert_equal "${baseline_thread_count}" "${final_thread_count}" 'worker thread count after client aborts'

post_abort_status="$(curl \
    --http1.1 \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${base_url}/contract?case=post-abort")"
assert_equal 200 "${post_abort_status}" 'service health after client aborts'

log "Client abort cleanup passed: final ${final_fd_count} FDs, ${final_thread_count} threads"
log 'All contract tests passed'
