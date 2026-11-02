package com.example.payments.application.port.in;

import com.example.payments.domain.AccountId;
import com.example.payments.domain.Money;
import java.util.Objects;

public interface TransferMoneyUseCase {

    TransferResult transfer(TransferCommand command);

    /** idempotencyKey is client-supplied; repeating a key returns the original result. */
    record TransferCommand(String idempotencyKey, AccountId from, AccountId to, Money amount) {
        public TransferCommand {
            Objects.requireNonNull(idempotencyKey, "idempotencyKey");
            Objects.requireNonNull(from, "from");
            Objects.requireNonNull(to, "to");
            Objects.requireNonNull(amount, "amount");
            if (from.equals(to)) {
                throw new IllegalArgumentException("Source and target accounts must differ");
            }
        }
    }

    record TransferResult(String transferId, Money fromBalance, Money toBalance) {}
}
