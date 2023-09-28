#!/bin/bash


GENERATOR=ShareGenerator
BINARY=fairyringd
CHAIN_DIR=$(pwd)/data
CHAINID_1=fairyring_test_1
CHAIN1_NODE=tcp://localhost:16657


FROM_ADDR=$1
BLOCK_TIME=$2
KEYSHARE_HEX=$3
SLEEP_BLOCK_TIME=$(($BLOCK_TIME/2))
KEYSHARE_INDEX=$4
TARGET_BLOCK_TO_SUBMIT=$5
SRC_PIPE=$6

check_tx_code () {
  local TX_CODE=$(echo "$1" | jq -r '.code')
  if [ "$TX_CODE" != 0 ]; then
    echo "ERROR: Tx failed with code: $TX_CODE"
    exit 1
  fi
}


wait_for_tx () {
  sleep $BLOCK_TIME
  local TXHASH=$(echo "$1" | jq -r '.txhash')
  RESULT=$($BINARY q tx --type=hash $TXHASH --home $CHAIN_DIR/$CHAINID_1 --chain-id $CHAINID_1 --node $CHAIN1_NODE -o json)
  echo "$RESULT"
}


# ./submitTx from_address block_time keyshare_hex keyshare_index target_block


ACCOUNT_INFO=$($BINARY query account $FROM_ADDR --home $CHAIN_DIR/$CHAINID_1 --chain-id $CHAINID_1 --node $CHAIN1_NODE -o json)
ACCOUNT_NUMBER=$(echo $ACCOUNT_INFO | jq -r '.account_number')
ACCOUNT_SEQ=$(echo $ACCOUNT_INFO | jq -r '.sequence')

echo "Testing Submit keyshare tx limit"

TARGET_HEIGHT=$(($TARGET_BLOCK_TO_SUBMIT+1))
echo "Expected Tx to be confirmed in lower or equals to block: $TARGET_HEIGHT"

EXTRACTED_RESULT=$($GENERATOR derive $KEYSHARE_HEX $KEYSHARE_INDEX $TARGET_HEIGHT)
EXTRACTED_SHARE=$(echo "$EXTRACTED_RESULT" | jq -r '.KeyShare')
EXTRACTED_COMMITMENT=$(echo "$EXTRACTED_RESULT" | jq -r '.Commitment')


while true
do
  if read line <$SRC_PIPE; then
    LATEST_BLOCK=$line
    echo "Current block: $LATEST_BLOCK, waiting until block: $TARGET_BLOCK_TO_SUBMIT"
    if [ "$LATEST_BLOCK" -ge "$TARGET_BLOCK_TO_SUBMIT" ]; then
      echo "$LATEST_BLOCK | $TARGET_BLOCK_TO_SUBMIT"
      echo "Current block: $LATEST_BLOCK, Start submitting tx..."
      break
    fi
    sleep 0.5
  fi
done


RESULT=$($BINARY tx keyshare send-keyshare $EXTRACTED_SHARE $EXTRACTED_COMMITMENT $KEYSHARE_INDEX $TARGET_HEIGHT --from $FROM_ADDR --offline --account-number $ACCOUNT_NUMBER --sequence $ACCOUNT_SEQ  --gas 600000 --home $CHAIN_DIR/$CHAINID_1 --chain-id $CHAINID_1 --node $CHAIN1_NODE --broadcast-mode async --keyring-backend test -o json -y)

SUBMITTED_TX_HASH=()
NEXT_BLOCK_CONFIRMED=0

TX_CODE=$(echo "$RESULT" | jq -r '.code')
TX_HASH=$(echo "$RESULT" | jq -r '.txhash')
echo "Tx Code: $TX_CODE, Tx Hash: $TX_HASH"
SUBMITTED_TX_HASH+=("$TX_HASH")

TX_HASH_LENGTH=${#SUBMITTED_TX_HASH[*]}

echo "Total Tx Hash: $TX_HASH_LENGTH"

sleep $(($BLOCK_TIME*3))

for EACH_TX_HASH in "${SUBMITTED_TX_HASH[@]}"
do
  RESP=$($BINARY q tx --type=hash $EACH_TX_HASH --home $CHAIN_DIR/$CHAINID_1 --chain-id $CHAINID_1 --node $CHAIN1_NODE -o json)
  CONFIRMED_BLOCK=$(echo $RESP | jq -r '.height')
  CONFIRMED_CODE=$(echo $RESP | jq -r '.code')
  echo "Tx Hash: $EACH_TX_HASH confirmed at block $CONFIRMED_BLOCK with code: $CONFIRMED_CODE"

  if [ "$CONFIRMED_BLOCK" -le "$TARGET_HEIGHT" ]; then
    if [ "$CONFIRMED_CODE" = "0" ]; then
      NEXT_BLOCK_CONFIRMED=$(($NEXT_BLOCK_CONFIRMED+1))
    fi
  fi

done

echo "Total Tx confirmed in next block: "
echo "$NEXT_BLOCK_CONFIRMED"
