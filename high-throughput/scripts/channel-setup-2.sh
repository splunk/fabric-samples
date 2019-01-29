#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#
set -x

export FABRIC_CFG_PATH=${PWD}/config
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

function createChannel() {
	CHANNEL_NAME=$1

	# Generate channel configuration transaction
	echo "========== Creating channel transaction for: "$CHANNEL_NAME" =========="
	configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ../channel-artifacts/$CHANNEL_NAME-channel.tx -channelID $CHANNEL_NAME
	res=$?
	if [ $res -ne 0 ]; then
	    echo "Failed to generate channel configuration transaction..."
	    exit 1
	fi	


	# Channel creation
	echo "========== Creating channel: "$CHANNEL_NAME" =========="
	peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ../channel-artifacts/$CHANNEL_NAME-channel.tx --tls $CORE_PEER_TLS_ENABLED --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
}

function joinChannel() {
	PEER_NAME=$1
	CHANNEL_NAME=$2
	MSP_ID=$3
	IS_ANCHOR=$4

	ORG_NAME=$( echo $PEER_NAME | cut -d. -f1 --complement)

	echo "========== Joining "$PEER_NAME" to channel "$CHANNEL_NAME" =========="
	export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/$ORG_NAME/users/Admin@$ORG_NAME/msp
	export CORE_PEER_ADDRESS=$PEER_NAME:7051
	export CORE_PEER_LOCALMSPID="$MSP_ID"
	export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/$ORG_NAME/peers/$PEER_NAME/tls/ca.crt
	peer channel join -b ${CHANNEL_NAME}.block

	if [ ${IS_ANCHOR} -ne 0 ]; then
		echo "========== Generating anchor peer definition for: "$CHANNEL_NAME" =========="
	    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../channel-artifacts/$CHANNEL_NAME-${CORE_PEER_LOCALMSPID}anchors.tx -channelID $CHANNEL_NAME -asOrg $MSP_ID

		res=$?
		if [ $res -ne 0 ]; then
		    echo "Failed to generate channel configuration transaction..."
		    exit 1
		fi	
		# if anchor then update this.
		peer channel update -o orderer.example.com:7050 -c ${CHANNEL_NAME} -f ../channel-artifacts/${CHANNEL_NAME}-${CORE_PEER_LOCALMSPID}anchors.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA
	fi
}

function installChaincode() {
	PEER_NAME=$1
	CHAINCODE_NAME=$2
	MSP_ID=$3
	VERSION=$4
	ORG_NAME=$( echo $PEER_NAME | cut -d. -f1 --complement)

	echo "========== Installing chaincode [${CHAINCODE_NAME}] on ${PEER_NAME} =========="
	export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}/users/Admin@${ORG_NAME}/msp
	export CORE_PEER_ADDRESS=${PEER_NAME}:7051
	export CORE_PEER_LOCALMSPID="${MSP_ID}"
	export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}/peers/${PEER_NAME}/tls/ca.crt
	peer chaincode install -n $CHAINCODE_NAME -v $VERSION -p github.com/hyperledger/fabric/examples/chaincode/go
}

function instantiateChaincode() {
	PEER_NAME=$1
	CHANNEL_NAME=$2
	CHAINCODE_NAME=$3
	MSP_ID=$4
	VERSION=$5

	ORG_NAME=$( echo $PEER_NAME | cut -d. -f1 --complement)

	echo "========== Instantiating chaincode [${CHAINCODE_NAME}] on ${PEER_NAME} in ${CHANNEL_NAME} =========="
	export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}/users/Admin@${ORG_NAME}/msp
	export CORE_PEER_ADDRESS=${PEER_NAME}:7051
	export CORE_PEER_LOCALMSPID="${MSP_ID}"
	export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG_NAME}/peers/${PEER_NAME}/tls/ca.crt
	peer chaincode instantiate -o orderer.example.com:7050 --tls $CORE_PEER_TLS_ENABLED \
		--cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
		-C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args": []}' \
		-v $VERSION -P "OR ('Org1MSP.member','Org2MSP.member')"
}


# # Create any number of channels here with new names.
createChannel "mychannel-one"
createChannel "mychannel-two"
createChannel "mychannel-three"

# Have any number of peers to join here. Third argument is Org1MSP or Org2MSP, last arg is 1 or 0 for anchor peer or not. Can only have 1 anchor peer per org per channel.
joinChannel "peer0.org1.example.com" "mychannel-three" "Org1MSP" 1
joinChannel "peer1.org1.example.com" "mychannel-three" "Org1MSP" 0
joinChannel "peer0.org2.example.com" "mychannel-three" "Org2MSP" 1
joinChannel "peer1.org2.example.com" "mychannel-three" "Org2MSP" 0

# Install chaincode onto peers. Do not worry about channels here.
installChaincode "peer0.org1.example.com" "splunk_cc" "Org1MSP" 1.0
installChaincode "peer1.org1.example.com" "splunk_cc" "Org1MSP" 1.0
installChaincode "peer0.org2.example.com" "splunk_cc" "Org2MSP" 1.0
installChaincode "peer1.org2.example.com" "splunk_cc" "Org2MSP" 1.0

# Instantiate chaincode on one ore more peers in each channel.
instantiateChaincode "peer0.org2.example.com" "mychannel-one" "splunk_cc" "Org2MSP" 1.0
instantiateChaincode "peer1.org2.example.com" "mychannel-two" "splunk_cc" "Org2MSP" 1.0
instantiateChaincode "peer0.org1.example.com" "mychannel-three" "splunk_cc" "Org2MSP" 1.0

