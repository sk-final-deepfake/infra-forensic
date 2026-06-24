-- PostgreSQL: missing tables (Hibernate clob -> text)
-- Safe to re-run: IF NOT EXISTS

CREATE TABLE IF NOT EXISTS evidence_manifests (
    evidence_id BIGINT PRIMARY KEY,
    created_at TIMESTAMP(6) NOT NULL,
    manifest_hash VARCHAR(64) NOT NULL,
    manifest_json TEXT NOT NULL,
    manifest_storage_path TEXT,
    signature_algorithm VARCHAR(50),
    signature_status VARCHAR(20) NOT NULL CHECK (signature_status IN ('SIGNED', 'UNSIGNED', 'FAILED')),
    signature_value TEXT,
    signed_at TIMESTAMP(6),
    signer_certificate_subject VARCHAR(500)
);

CREATE TABLE IF NOT EXISTS blockchain_anchors (
    anchor_id BIGSERIAL PRIMARY KEY,
    anchor_type VARCHAR(30) NOT NULL CHECK (anchor_type IN ('EVIDENCE_HASH', 'REPORT_HASH', 'MERKLE_ROOT')),
    subject_hash VARCHAR(64) NOT NULL,
    evidence_id BIGINT,
    report_id BIGINT,
    created_by BIGINT,
    merkle_batch_date DATE,
    merkle_leaf_count INTEGER,
    status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'ANCHORED', 'FAILED')),
    transaction_hash VARCHAR(128),
    block_number BIGINT,
    network VARCHAR(50),
    anchored_at TIMESTAMP(6),
    created_at TIMESTAMP(6) NOT NULL,
    error_message TEXT
);

CREATE INDEX IF NOT EXISTS idx_blockchain_anchors_evidence_id ON blockchain_anchors (evidence_id);
CREATE INDEX IF NOT EXISTS idx_blockchain_anchors_report_id ON blockchain_anchors (report_id);
