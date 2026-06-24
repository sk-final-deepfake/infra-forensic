const fs = require("fs");
const crypto = require("crypto");
const grpc = require("@grpc/grpc-js");
const { connect, hash, signers } = require("@hyperledger/fabric-gateway");

let gatewayPromise;

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || !String(value).trim()) {
    throw new Error(`Missing env: ${name}`);
  }
  return value;
}

async function getGateway() {
  if (!gatewayPromise) {
    gatewayPromise = createGateway();
  }
  return gatewayPromise;
}

async function createGateway() {
  const tlsCertPath = requiredEnv("FABRIC_TLS_CERT_PATH");
  const peerEndpoint = requiredEnv("FABRIC_PEER_ENDPOINT");
  const mspId = requiredEnv("FABRIC_MSP_ID");
  const certPath = requiredEnv("FABRIC_CERT_PATH");
  const keyPath = requiredEnv("FABRIC_KEY_PATH");

  const tlsRootCert = fs.readFileSync(tlsCertPath);
  const credentials = grpc.credentials.createSsl(tlsRootCert);
  const client = new grpc.Client(peerEndpoint, credentials, {
    "grpc.ssl_target_name_override": process.env.FABRIC_PEER_HOST_ALIAS || "peer0.org1.example.com",
  });

  const certificate = fs.readFileSync(certPath);
  const privateKeyPem = fs.readFileSync(keyPath);
  const privateKey = crypto.createPrivateKey(privateKeyPem);
  const identity = { mspId, credentials: certificate };
  const signer = signers.newPrivateKeySigner(privateKey);

  return connect({
    client,
    identity,
    signer,
    hash: hash.sha256,
  });
}

async function getContract() {
  const gateway = await getGateway();
  const channelName = process.env.FABRIC_CHANNEL || "forenshield-evidence";
  const chaincodeName = process.env.FABRIC_CHAINCODE || "anchor";
  const network = gateway.getNetwork(channelName);
  return network.getContract(chaincodeName);
}

async function submitAnchor(payload) {
  const contract = await getContract();
  const evidenceId = payload.evidenceId == null ? "" : String(payload.evidenceId);
  const reportId = payload.reportId == null ? "" : String(payload.reportId);
  const merkleBatchDate = payload.merkleBatchDate == null ? "" : String(payload.merkleBatchDate);
  const merkleLeafCount = payload.merkleLeafCount == null ? "" : String(payload.merkleLeafCount);
  const clientId = payload.clientId || "forenshield-be";

  const commit = await contract.submitAsync("AnchorHash", {
    arguments: [
      payload.subjectHash,
      payload.anchorType,
      clientId,
      evidenceId,
      reportId,
      merkleBatchDate,
      merkleLeafCount,
    ],
  });

  const txId = commit.getTransactionId();
  const resultBytes = await commit.getResult();
  const status = await commit.getStatus();

  return {
    txId,
    blockNumber: Number(status.blockNumber),
    payload: resultBytes.length ? resultBytes.toString("utf8") : "",
  };
}

async function closeGateway() {
  if (gatewayPromise) {
    const gateway = await gatewayPromise;
    gateway.close();
    gatewayPromise = undefined;
  }
}

module.exports = {
  submitAnchor,
  closeGateway,
};
