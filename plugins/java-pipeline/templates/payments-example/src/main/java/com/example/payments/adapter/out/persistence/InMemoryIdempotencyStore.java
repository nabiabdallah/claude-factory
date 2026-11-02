package com.example.payments.adapter.out.persistence;

import com.example.payments.application.port.in.TransferMoneyUseCase.TransferResult;
import com.example.payments.application.port.out.IdempotencyStore;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

public class InMemoryIdempotencyStore implements IdempotencyStore {

    private final Map<String, TransferResult> results = new ConcurrentHashMap<>();

    @Override
    public Optional<TransferResult> find(String idempotencyKey) {
        return Optional.ofNullable(results.get(idempotencyKey));
    }

    @Override
    public void remember(String idempotencyKey, TransferResult result) {
        results.putIfAbsent(idempotencyKey, result);
    }
}
