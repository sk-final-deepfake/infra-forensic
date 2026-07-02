package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type AnchorRecord struct {
	SubjectHash     string `json:"subjectHash"`
	AnchorType      string `json:"anchorType"`
	ClientID        string `json:"clientId"`
	EvidenceID      string `json:"evidenceId,omitempty"`
	ReportID        string `json:"reportId,omitempty"`
	MerkleBatchDate string `json:"merkleBatchDate,omitempty"`
	MerkleLeafCount string `json:"merkleLeafCount,omitempty"`
	AnchoredAt      string `json:"anchoredAt"`
	TxID            string `json:"txId,omitempty"`
}

type AnchorContract struct {
	contractapi.Contract
}

func (c *AnchorContract) AnchorHash(
	ctx contractapi.TransactionContextInterface,
	subjectHash string,
	anchorType string,
	clientId string,
	evidenceId string,
	reportId string,
	merkleBatchDate string,
	merkleLeafCount string,
) error {
	subjectHash = strings.TrimSpace(subjectHash)
	anchorType = strings.TrimSpace(anchorType)
	if subjectHash == "" || anchorType == "" {
		return fmt.Errorf("subjectHash and anchorType are required")
	}

	key, err := composeKey(anchorType, subjectHash, evidenceId, reportId, merkleBatchDate)
	if err != nil {
		return err
	}

	existing, err := ctx.GetStub().GetState(key)
	if err != nil {
		return err
	}
	if existing != nil {
		return nil
	}

	record := AnchorRecord{
		SubjectHash:     subjectHash,
		AnchorType:      anchorType,
		ClientID:        clientId,
		EvidenceID:      evidenceId,
		ReportID:        reportId,
		MerkleBatchDate: merkleBatchDate,
		MerkleLeafCount: merkleLeafCount,
		AnchoredAt:      time.Now().UTC().Format(time.RFC3339),
		TxID:            ctx.GetStub().GetTxID(),
	}
	bytes, err := json.Marshal(record)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(key, bytes)
}

func (c *AnchorContract) GetAnchor(
	ctx contractapi.TransactionContextInterface,
	anchorType string,
	lookupKey string,
) (string, error) {
	key, err := composeLookupKey(anchorType, lookupKey)
	if err != nil {
		return "", err
	}
	bytes, err := ctx.GetStub().GetState(key)
	if err != nil {
		return "", err
	}
	if bytes == nil {
		return "", fmt.Errorf("anchor not found: %s", key)
	}
	return string(bytes), nil
}

func composeKey(anchorType, subjectHash, evidenceId, reportId, merkleBatchDate string) (string, error) {
	switch anchorType {
	case "EVIDENCE_HASH":
		if strings.TrimSpace(evidenceId) == "" {
			return "", fmt.Errorf("evidenceId required for EVIDENCE_HASH")
		}
		return fmt.Sprintf("EVIDENCE:%s", evidenceId), nil
	case "REPORT_HASH":
		if strings.TrimSpace(reportId) == "" {
			return "", fmt.Errorf("reportId required for REPORT_HASH")
		}
		return fmt.Sprintf("REPORT:%s", reportId), nil
	case "MERKLE_ROOT":
		if strings.TrimSpace(merkleBatchDate) == "" {
			return "", fmt.Errorf("merkleBatchDate required for MERKLE_ROOT")
		}
		return fmt.Sprintf("MERKLE:%s", merkleBatchDate), nil
	default:
		return fmt.Sprintf("HASH:%s:%s", anchorType, subjectHash), nil
	}
}

func composeLookupKey(anchorType, lookupKey string) (string, error) {
	switch anchorType {
	case "EVIDENCE_HASH":
		return fmt.Sprintf("EVIDENCE:%s", lookupKey), nil
	case "REPORT_HASH":
		return fmt.Sprintf("REPORT:%s", lookupKey), nil
	case "MERKLE_ROOT":
		return fmt.Sprintf("MERKLE:%s", lookupKey), nil
	default:
		return "", fmt.Errorf("unsupported anchorType: %s", anchorType)
	}
}

func main() {
	chaincode, err := contractapi.NewChaincode(&AnchorContract{})
	if err != nil {
		panic(fmt.Sprintf("chaincode init: %v", err))
	}
	if err := chaincode.Start(); err != nil {
		panic(fmt.Sprintf("chaincode start: %v", err))
	}
}
