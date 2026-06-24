-- Fix notifications_type_check: add SECURITY_ALERT (RQ-SEC-153)
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
        'ANALYSIS_COMPLETED',
        'ANALYSIS_FAILED',
        'BLOCKCHAIN_ANCHOR',
        'SECURITY_ALERT'
    ));
