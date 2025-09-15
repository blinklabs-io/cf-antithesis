#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

export ANTI_WAIT=180

unset ANTI_TOKEN_ID

log "Using ANTI_MPFS_HOST: $ANTI_MPFS_HOST"

log "Creating an anti token..."
result=$(anti oracle token boot)

tokenId=$(echo "$result" | jq -r '.value')
log "Anti token ID: $tokenId"

owner=$(anti wallet info | jq -r '.owner')

export ANTI_TOKEN_ID="$tokenId"

tokenEnd() {
    log "Ending anti token $ANTI_TOKEN_ID..."
    anti oracle token end >/dev/null || echo "Failed to end the token"
}
trap 'tokenEnd' EXIT INT TERM

resultReg1=$(anti requester register-user \
    --platform github \
    --username cfhal \
    --pubkeyhash AAAAC3NzaC1lZDI1NTE5AAAAILjwzNvy87HbzYV2lsW3UjVoxtpq4Nrj84kjo3puarCH)

outputRegRef1=$(getOutputRef "$resultReg1")

log "Created registration request with valid public key with output reference: $outputRegRef1"

if [ -z "$ANTI_GITHUB_PAT" ]; then
    log "Error: ANTI_GITHUB_PAT is not set. Please refer to \"https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens\#creating-a-fine-grained-personal-access-token\""
    exit 1
fi

resultVal1=$(anti token | jq -r '.requests | [.[] | select(.validation == "validated") | {"reference": .request.outputRefId, "validation": .validation}]')

expectedVal1=$(
    cat <<EOF
[
  {
    "reference": "$outputRegRef1",
    "validation": "validated"
  }
]
EOF
)

emitMismatch() {
    log "$2 result does not match expected value:"
    log "    Actual $2 $1 result: $3"
    log "    Expected $2 validation $1 result: $4"
    exit 1
}

if [[ "$(echo "$resultVal1" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal1" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 1 "validation" "$resultVal1" "$expectedVal1"
fi

log "Trying to create registration request with invalid public key"

resultReg2=$(anti requester register-user \
    --platform github \
    --username cfhal \
    --pubkeyhash AAAAC3NzaC1lZDI1NTE5AAAAILjwzNvy87HbzYV2lsW3UjVoxtpq4Nrj84djo3puarCH)

outputRegRes2=$(echo $resultReg2 | jq)
log "resultReg2: $resultReg2"

expectedRegRes2=$(
    cat <<EOF
{
  "validationFailed": {
    "publicKeyValidationFailure": "The user does not have the specified Ed25519 public key exposed in Github."
  }
}
EOF
)

if [[ "$(echo "$outputRegRes2")" != "$(echo "$expectedRegRes2")" ]]; then
    emitMismatch 1 "incorrect request" "$outputRegRes2" "$expectedRegRes2"
fi

resultVal2=$(anti token | jq -r '.requests | [.[] | select(.validation == "validated") | {"reference": .request.outputRefId, "validation": .validation}]')

expectedVal2=$(
    cat <<EOF
[
  {
    "reference": "$outputRegRef1",
    "validation": "validated"
  }
]
EOF
)

if [[ "$(echo "$resultVal2" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal2" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 2 "validation" "$resultVal2" "$expectedVal2"
fi

log "Registering a role before token updating with user registration fact is possible"

resultRole1=$(anti requester register-role \
    --platform github \
    --repository cardano-foundation/hal-fixture-sin \
    --username cfhal \
    )
outputRoleRef1=$(getOutputRef "$resultRole1")

log "Created role registration request with output reference: $outputRoleRef1"
resultVal3=$(anti token | jq -r '.requests | [.[] | select(.validation == "validated") | {"reference": .request.outputRefId, "validation": .validation}]')

expectedVal3=$(
    cat <<EOF
[
  {
    "reference": "$outputRegRef1",
    "validation": "validated"
  },
  {
    "reference": "$outputRoleRef1",
    "validation": "validated"
  }
]
EOF
)

if [[ "$(echo "$resultVal3" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal3" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 3 "validation" "$resultVal3" "$expectedVal3"
fi

log "Including the registration user as the fact in the updaed token."
anti oracle token update -o "$outputRegRef1" >/dev/null

printFacts

expectedGet1=$(
    cat <<EOF
[
  {
    "request": {
        "change": {
            "key": "{\"platform\":\"github\",\"repository\":{\"organization\":\"cardano-foundation\",\"project\":\"hal-fixture-sin\"},\"type\":\"register-role\",\"user\":\"cfhal\"}",
            "type": "insert",
            "value": "null"
            },
        "outputRefId": "$outputRoleRef1",
        "owner": "$owner"
        },
    "validation": "validated"
  }
]
EOF
)

resultGet1=$(anti token | jq '.requests')

if [[ "$(echo "$resultGet1" | jq -S 'sort_by(.request.outputRefId)')" != "$(echo "$expectedGet1" | jq -S 'sort_by(.request.outputRefId)')" ]]; then
    emitMismatch 4 "get token requests" "$resultGet1" "$expectedGet1"
fi

resultVal4=$(anti token | jq -r '.requests | [.[] | select(.validation == "validated") | {"reference": .request.outputRefId, "validation": .validation}]')

expectedVal4=$(
    cat <<EOF
[
  {
    "reference": "$outputRoleRef1",
    "validation": "validated"
  }
]
EOF
)

if [[ "$(echo "$resultVal4" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal4" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 5 "validation" "$resultVal4" "$expectedVal4"
fi

log "Including the role request that passed validation in the token ..."
anti oracle token update -o "$outputRoleRef1" >/dev/null

printFacts

expectedGet2=$(
    cat <<EOF
[]
EOF
)

resultGet2=$(anti token | jq '.requests')

if [[ "$(echo "$resultGet2" | jq -S 'sort_by(.request.outputRefId)')" != "$(echo "$expectedGet2" | jq -S 'sort_by(.request.outputRefId)')" ]]; then
    emitMismatch 6 "get token requests" "$resultGet2" "$expectedGet2"
fi

resultUnRole1=$(anti requester unregister-role \
    --platform github \
    --repository cardano-foundation/hal-fixture-sin \
    --username cfhal \
    )
outputUnRoleRef1=$(getOutputRef "$resultUnRole1")

log "Created role unregistration request with output reference: $outputUnRoleRef1"
resultVal5=$(anti token | jq -r '.requests | [.[] | select(.validation == "validated") | {"reference": .request.outputRefId, "validation": .validation}]')

expectedVal5=$(
    cat <<EOF
[
  {
    "reference": "$outputUnRoleRef1",
    "validation": "validated"
  }
]
EOF
)

if [[ "$(echo "$resultVal5" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal5" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 7 "validation" "$resultVal5" "$expectedVal5"
fi

resultUnRole2=$(anti requester unregister-role \
    --platform github \
    --repository cardano-foundation/hal-fixture-sinn \
    --username cfhal \
    )

outputUnRoleRes2=$(echo $resultUnRole2 | jq)
log "resultUnRole2: $resultUnRole2"

log "Created role unregistration request with incorrect repository"

expectedUnRoleRes2=$(
    cat <<EOF

{
"validationFailed": {
    "unregisterRoleKeyFailure": {
        "keyDoesNotExist":
        "RegisterRoleKey {platform = Platform \"github\", repository = Repository {organization = \"cardano-foundation\", project = \"hal-fixture-sinn\"}, username = Username \"cfhal\"}"
        }
    }
}

EOF
)


if [[ "$(echo "$outputUnRoleRes2" | jq)" != "$(echo "$expectedUnRoleRes2" | jq)" ]]; then
    emitMismatch 8 "incorrect request" "$outputUnRoleRes2" "$expectedUnRoleRes2"
fi

resultVal6=$(anti token | jq -r '.requests | [.[] | select(.validation == "validated") | {"reference": .request.outputRefId, "validation": .validation}]')

expectedVal6=$(
    cat <<EOF
[
  {
    "reference": "$outputUnRoleRef1",
    "validation": "validated"
  }
]
EOF
)

if [[ "$(echo "$resultVal6" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal6" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 9 "validation" "$resultVal6" "$expectedVal6"
fi

resultUnReg1=$(anti requester unregister-user \
    --platform github \
    --username cfhal \
    --pubkeyhash AAAAC3NzaC1lZDI1NTE5AAAAILjwzNvy87HbzYV2lsW3UjVoxtpq4Nrj84kjo3puarCH)

outputUnRegRef1=$(getOutputRef "$resultUnReg1")

log "Created unregistration request with valid public key with output reference: $outputUnRegRef1"
resultVal7=$(anti token | jq -r '.requests | [.[] | select(.validation == "validated") | {"reference": .request.outputRefId, "validation": .validation}]')

expectedVal7=$(
    cat <<EOF
[
  {
    "reference": "$outputUnRoleRef1",
    "validation": "validated"
  },
  {
    "reference": "$outputUnRegRef1",
    "validation": "validated"
  }
]
EOF
)

if [[ "$(echo "$resultVal7" | jq -S 'sort_by(.reference)')" != "$(echo "$expectedVal7" | jq -S 'sort_by(.reference)')" ]]; then
    emitMismatch 10 "validation" "$resultVal7" "$expectedVal7"
fi

log "Including the role and user unregistration requests that passed validation in the token ..."
anti oracle token update -o "$outputUnRoleRef1" -o "$outputUnRegRef1"  >/dev/null

printFacts

expectedGet3=$(
    cat <<EOF
[]
EOF
)

resultGet3=$(anti token | jq '.requests')

if [[ "$(echo "$resultGet3" | jq -S 'sort_by(.request.outputRefId)')" != "$(echo "$expectedGet3" | jq -S 'sort_by(.request.outputRefId)')" ]]; then
    emitMismatch 11 "get token requests" "$resultGet3" "$expectedGet3"
fi
