#!/usr/bin/env bash

# Client ID Variable
CID=""
CSECRET=""

##############################################
## GETOPT VARIABLES + ARGUMENT PARSING START##
##############################################

# Initializing other variables that will be taking in via getopt
unset -v ORGID

# Arguments for script
LONG_ARGS="orgid:,help"
SHORT_ARGS="o:,h"

# Help Function
function help()
{
    echo "Based on standards I found on the internet - MPM"
    echo "Usage: ${0}
               -o | --orgid           Org Id
               -h | --help            Help Menu"
    exit 2
}

OPTS=$(getopt --options ${SHORT_ARGS} --longoptions ${LONG_ARGS} -- "$@")
eval set -- "${OPTS}"
while :
do
  case "$1" in
    -o | --orgid )
        ORGID="$2"
        shift 2
        ;;
    -h | --help )
      help
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      help
      ;;
  esac
done

if [ -z "${ORGID}" ]; then
  echo "Missing argument!"
  help
fi

echo "Updating Org: ${ORGID}"

##############################################
## GETOPT VARIABLES + ARGUMENT PARSING END  ##
##############################################

##############################################
##                CONSTANTS                 ##
##############################################
# URIs
APOINTBASE="https://anypoint.mulesoft.com/"
TOKENURI="${APOINTBASE}/accounts/api/v2/oauth2/token"
MEURI="${APOINTBASE}/accounts/api/profile"
ORGSURI="${APOINTBASE}/accounts/api/organizations"
PSALLURI="${APOINTBASE}/runtimefabric/api/organizations/${ORGID}/privatespaces"

##############################################
##                FUNCTIONS                 ##
##############################################

function anypoint_login() {
    local FULLTOKEN=$(curl -s -X POST -d "client_id=${CID}&client_secret=${CSECRET}&grant_type=client_credentials" ${TOKENURI})
    echo ${FULLTOKEN} | jq -r .access_token
}

function anypoint_add_route() {
    local PSID=${1}
    local CIDR_REGEX="^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$"
    local VPNCONNSURI="${PSALLURI}/${PSID}/connections"
    local TGWCONNSURI="${PSALLURI}/${PSID}/transitgateways"

    anypoint_choose_connection CONNID $PSID

    local CONNURI=""
    if [[ $CONNID == tgw* ]]; then
        CONNURI="${TGWCONNSURI}/${CONNID}"
    else
        CONNURI="${VPNCONNSURI}/${CONNID}"
    fi;

    # # Get all existing ROUTEs for that connection
    local CONNECTION=$(curl -s ${CONNURI} -H "Accept: application/json" -H "Authorization: Bearer ${TOKEN}")
    ROUTES=$(echo ${CONNECTION} | jq -r ".status.routes")

    local CIDR=""

    while [[ ! $CIDR =~ $CIDR_REGEX  ]] ; do 
        read -p "What is the CIDR we're adding to this PrivateSpace Route? " CIDR
        if [[ ! $CIDR =~ $CIDR_REGEX ]]; then
            echo "Sorry! '${CIDR}' is not a valid CIDR for a route. Please try again"
        fi
    done

    local NEW_ROUTES=$(jq -n --argjson routes "${ROUTES}" --arg cidr "${CIDR}" '$routes + [$cidr]')
    # local PATCH_PAYLOAD=$(jq -n --argjson routes "${NEW_ROUTES}" --arg connid "${CONNID}" '{networkGateways: [{routes: $routes, target: $connid}]}')
    local PATCH_PAYLOAD=$(jq -n --argjson routes "${NEW_ROUTES}" --arg connid "${CONNID}" '{routes: $routes}')

    echo "Updating Private Space: '${PSID}' with new properties now."
    # echo "Calling: ${CONNURI}"
    # echo ${PATCH_PAYLOAD}
    # echo ""
    QUIETYOU=$(curl -s -X PATCH ${CONNURI} -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "${PATCH_PAYLOAD}")
    echo "Please use the below payload to validate execution"
    echo ${QUIETYOU}
}

function anypoint_choose_connection() {
    local -n __RET=${1}
    local PSID=${2}
    local VPNCONNSURI="${PSALLURI}/${PSID}/connections"
    local TGWCONNSURI="${PSALLURI}/${PSID}/transitgateways"
    local PSCONNS_ARR=()
    
    #
    local VPNCONNS=$(curl -s ${VPNCONNSURI} -H "Accept: application/json" -H "Authorization: Bearer ${TOKEN}")
    local TGWCONNS=$(curl -s ${TGWCONNSURI} -H "Accept: application/json" -H "Authorization: Bearer ${TOKEN}")

    local CONNECTIONS_ARR=$(jq -n --argjson arr1 "${VPNCONNS}" --argjson arr2 "${TGWCONNS}" '$arr1 + $arr2')
    
    for CON in $(echo "${CONNECTIONS_ARR}" | jq -r ".[].name"); do
        PSCONNS_ARR+=("${CON}")
    done;

    prompt_choice CONNAME 'Which connection are adding the route to?' "${PSCONNS_ARR[@]}"
    
    __RET=$(echo "${CONNECTIONS_ARR}" | jq -r ". | map(select(.name == \"${CONNAME}\")) | first | .id")

    echo "Connection Chosen: ${__RET}"

    if [ -z "${__RET}" ]; then
        echo "ERROR! Couldn't get ID of Connection '${__RET}'"
        echo ${VPNCONNS}
        echo ${TGWCONNS}
        exit 1;
    fi
}

function anypoint_choose_private_space() {
    echo "Getting all private spaces"
    local -n __RET=${1}
    local PSSPACES=$(curl -s ${PSALLURI} -H "Accept: application/json" -H "Authorization: Bearer ${TOKEN}")
    local PSNAME_ARR=()
    
    for PS in $(echo "${PSSPACES}" | jq -r ".content[].name"); do
        PSNAME_ARR+=("${PS}")
    done;

    prompt_choice PSNAME 'Which Private Space would you like to edit?' "${PSNAME_ARR[@]}"
    __RET=$(echo "${PSSPACES}" | jq -r ".content | map(select(.name == \"${PSNAME}\")) | first | .id")

    if [ -z "${__RET}" ]; then
        echo "ERROR! Couldn't get ID of Private Space with name '${SPACE}'"
        echo ${PSSPACES}
        exit 1;
    fi
}

function prompt_choice() {
  if [ -z "${1}" ]; then
    echo "Error! You need to pass in a parameter!"
    echo "  ${0} 'Do you like apples?' ('Yes' 'No')"
    exit 1
  fi;
  local -n CHOICE=${1}
  local MSG=${2}
  shift 2;
  local OPTIONS=("$@")


  local MIN=1
  local MAX=${#OPTIONS[@]}
  local OPT=-1
  CHOICE="!@#$%^&*()"

  if [[ ${MAX} -gt 1 ]]; then
    while [[ "${OPT}" -lt ${MIN} || "${OPT}" -gt ${MAX} ]]; do
      for i in "${!OPTIONS[@]}"; do
        echo "$(($i+1))   ${OPTIONS[$i]}"
      done
      read -p "${MSG} " OPT
      if [[ "${OPT}" -ge ${MIN} && "${OPT}" -le ${MAX} ]]; then
        CHOICE="${OPTIONS[$((${OPT}-1))]}"
      fi
    done;
  else
    CHOICE="${OPTIONS[0]}"
  fi;
}

##############################################
##              END FUNCTIONS               ##
##############################################

##############################################
##              MAIN FUNCTION               ##
##############################################

function main() {
    TOKEN=$(anypoint_login)

    anypoint_choose_private_space PSID
    anypoint_add_route $PSID
}

main
