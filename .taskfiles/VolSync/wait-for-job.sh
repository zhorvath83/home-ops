#!/usr/bin/env bash

JOB_NAME=$1
NAMESPACE="${2:-default}"
START_TIME=$SECONDS
TIMEOUT_SECONDS=120

[[ -z "${JOB_NAME}" ]] && echo "Job name not specified" && exit 1

while true; do
    PODS="$(kubectl -n "${NAMESPACE}" get pod -l job-name="${JOB_NAME}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
    COMPLETE="$(kubectl -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)"
    FAILED="$(kubectl -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)"

    if [[ -n "${PODS}" ]] || [[ "${COMPLETE}" == "True" ]] || [[ "${FAILED}" == "True" ]]; then
        break
    fi

    if (( SECONDS - START_TIME >= TIMEOUT_SECONDS )); then
        echo "Timed out waiting for job pod creation: ${JOB_NAME} in namespace ${NAMESPACE}" >&2
        exit 1
    fi

    sleep 1
done
