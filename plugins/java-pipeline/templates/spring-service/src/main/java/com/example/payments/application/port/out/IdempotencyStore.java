package com.example.payments.application.port.out;

import com.example.payments.application.port.in.TransferMoneyUseCase.TransferResult;
import java.util.Optional;

public interface IdempotencyStore {

    Optional<TransferResult> find(String idempotencyKey);

    void remember(String idempotencyKey, TransferResult result);
}
