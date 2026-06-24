require("dotenv").config();

const express = require("express");
const { submitAnchor } = require("./fabric");

const PORT = Number(process.env.GATEWAY_PORT || 8088);
const API_KEY = process.env.GATEWAY_API_KEY || "";

const app = express();
app.use(express.json({ limit: "64kb" }));

function checkApiKey(req, res, next) {
  if (!API_KEY) {
    return next();
  }
  const header = req.get("X-Api-Key");
  if (header !== API_KEY) {
    return res.status(401).json({ error: "unauthorized" });
  }
  return next();
}

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "forenshield-fabric-anchor-gateway",
    channel: process.env.FABRIC_CHANNEL || "forenshield-evidence",
    chaincode: process.env.FABRIC_CHAINCODE || "anchor",
  });
});

app.post("/api/v1/anchor", checkApiKey, async (req, res) => {
  const body = req.body || {};
  const subjectHash = body.subjectHash;
  const anchorType = body.anchorType;

  if (!subjectHash || !anchorType) {
    return res.status(400).json({ error: "subjectHash and anchorType are required" });
  }

  try {
    const submit = await submitAnchor(body);
    return res.json({
      transactionHash: submit.txId,
      blockNumber: submit.blockNumber,
      network: body.network || process.env.FABRIC_NETWORK_LABEL || "hyperledger-fabric-forenshield",
      chaincodeResponse: submit.payload || null,
    });
  } catch (err) {
    console.error("anchor failed", err);
    return res.status(502).json({
      error: "fabric_submit_failed",
      message: err.message || String(err),
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Fabric Anchor Gateway listening on http://0.0.0.0:${PORT}`);
  console.log(`POST http://0.0.0.0:${PORT}/api/v1/anchor`);
});
