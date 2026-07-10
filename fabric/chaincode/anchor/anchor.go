package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// OffchainRef points to off-chain detail locations (no payload content).
type OffchainRef struct {
	ManifestStoragePath string `json:"manifestStoragePath,omitempty"`
	OriginalStoragePath string `json:"originalStoragePath,omitempty"`
	ReportStoragePath   string `json:"reportStoragePath,omitempty"`
	CustodyLogBundleRef string `json:"custodyLogBundleRef,omitempty"`
}

type AnalysisModelRef struct {
	Name       string `json:"name,omitempty"`
	Version    string `json:"version,omitempty"`
	Identifier string `json:"identifier,omitempty"`
}

type AnalysisModuleRef struct {
	Module  string `json:"module,omitempty"`
	Name    string `json:"name,omitempty"`
	Version string `json:"version,omitempty"`
}

// AnchorRecord is the immutable ledger value for a hash anchor.
type AnchorRecord struct {
	SubjectHash     string              `json:"subjectHash"`
	AnchorType      string              `json:"anchorType"`
	ClientID        string              `json:"clientId"`
	EvidenceID      string              `json:"evidenceId,omitempty"`
	ReportID        string              `json:"reportId,omitempty"`
	MerkleBatchDate string              `json:"merkleBatchDate,omitempty"`
	MerkleLeafCount string              `json:"merkleLeafCount,omitempty"`
	Signature       string              `json:"signature,omitempty"`
	SignerCertHash  string              `json:"signerCertHash,omitempty"`
	CertVerified    *bool               `json:"certVerified,omitempty"`
	OffchainLogHash string              `json:"offchainLogHash,omitempty"`
	OffchainRef     *OffchainRef        `json:"offchainRef,omitempty"`
	AnalysisModel   *AnalysisModelRef   `json:"analysisModel,omitempty"`
	AnalysisModules []AnalysisModuleRef `json:"analysisModules,omitempty"`
	AnchoredAt      string              `json:"anchoredAt"`
	TxID            string              `json:"txId,omitempty"`
}

type AnchorContract struct {
	contractapi.Contract
}

// AnchorHash stores an immutable anchor record.
// Extended fields (signature, signerCertHash, certVerified, offchainLogHash, offchainRefJson)
// are optional strings; empty means omit from the ledger record.
func (c *AnchorContract) AnchorHash(
	ctx contractapi.TransactionContextInterface,
	subjectHash string,
	anchorType string,
	clientId string,
	evidenceId string,
	reportId string,
	merkleBatchDate string,
	merkleLeafCount string,
	signature string,
	signerCertHash string,
	certVerified string,
	offchainLogHash string,
	offchainRefJson string,
	analysisModelJson string,
	analysisModulesJson string,
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
		EvidenceID:      strings.TrimSpace(evidenceId),
		ReportID:        strings.TrimSpace(reportId),
		MerkleBatchDate: strings.TrimSpace(merkleBatchDate),
		MerkleLeafCount: strings.TrimSpace(merkleLeafCount),
		Signature:       strings.TrimSpace(signature),
		SignerCertHash:  strings.TrimSpace(signerCertHash),
		CertVerified:    parseOptionalBool(certVerified),
		OffchainLogHash: strings.TrimSpace(offchainLogHash),
		OffchainRef:     parseOffchainRef(offchainRefJson),
		AnalysisModel:   parseAnalysisModel(analysisModelJson),
		AnalysisModules: parseAnalysisModules(analysisModulesJson),
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

func parseOptionalBool(value string) *bool {
	switch strings.TrimSpace(strings.ToLower(value)) {
	case "true", "1":
		v := true
		return &v
	case "false", "0":
		v := false
		return &v
	default:
		return nil
	}
}

func parseOffchainRef(raw string) *OffchainRef {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var ref OffchainRef
	if err := json.Unmarshal([]byte(raw), &ref); err != nil {
		return nil
	}
	if ref.ManifestStoragePath == "" && ref.OriginalStoragePath == "" &&
		ref.ReportStoragePath == "" && ref.CustodyLogBundleRef == "" {
		return nil
	}
	return &ref
}

func parseAnalysisModel(raw string) *AnalysisModelRef {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var model AnalysisModelRef
	if err := json.Unmarshal([]byte(raw), &model); err != nil {
		return nil
	}
	if model.Name == "" && model.Version == "" && model.Identifier == "" {
		return nil
	}
	return &model
}

func parseAnalysisModules(raw string) []AnalysisModuleRef {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var modules []AnalysisModuleRef
	if err := json.Unmarshal([]byte(raw), &modules); err != nil {
		return nil
	}
	filtered := make([]AnalysisModuleRef, 0, len(modules))
	for _, module := range modules {
		if module.Module == "" && module.Name == "" && module.Version == "" {
			continue
		}
		filtered = append(filtered, module)
	}
	if len(filtered) == 0 {
		return nil
	}
	return filtered
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
