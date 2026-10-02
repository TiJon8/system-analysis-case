CREATE TYPE payment_status AS ENUM ('PENDING', 'PROCESSING', 'SUCCESS', 'FAILED', 'CANCELLED');
CREATE TYPE payment_method AS ENUM ('CARD', 'SBP');

CREATE TABLE IF NOT EXISTS users (
    user_id UUID PRIMARY KEY DEFAULT uuidv4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS payments (
    payment_id UUID PRIMARY KEY DEFAULT uuidv4(),
    idempotency_key UUID NOT NULL UNIQUE,
    user_id UUID NOT NULL REFERENCES users(user_id),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'RUB',
    status payment_status NOT NULL DEFAULT 'PENDING',
    payment_method payment_method NOT NULL,
	-- id во внешнем шлюзе
    external_provider_id VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION payments_set_updated_at RETURNS trigger AS $$
BEGIN
	NEW.updated_at := NOW();
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER payments_before_update
BEFORE UPDATE on payments
FOR EACH ROW
EXECUTE FUNCTION payments_set_updated_at();

CREATE TABLE IF NOT EXISTS payment_status_logs (
    log_id BIGSERIAL PRIMARY KEY,
    payment_id UUID NOT NULL REFERENCES payments(payment_id) ON DELETE CASCADE,
    old_status payment_status,
    new_status payment_status NOT NULL,
    reason TEXT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_status_created ON payments(status, created_at);
CREATE INDEX idx_payments_idempotency ON payments(idempotency_key);