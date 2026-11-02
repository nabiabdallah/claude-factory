package com.example.payments.application;

import com.example.payments.application.port.in.TransferMoneyUseCase;
import com.example.payments.application.port.out.AccountRepository;
import com.example.payments.application.port.out.IdempotencyStore;
import com.example.payments.domain.Account;
import com.example.payments.domain.AccountId;
import com.example.payments.domain.AccountNotFoundException;
import java.util.UUID;

/**
 * Framework-free use case. Wired as a bean in config/. Transaction boundaries belong to the
 * persistence adapter or config layer once a real database is added (record that in an ADR).
 */
public class TransferMoneyService implements TransferMoneyUseCase {

    private final AccountRepository accounts;
    private final IdempotencyStore idempotency;

    public TransferMoneyService(AccountRepository accounts, IdempotencyStore idempotency) {
        this.accounts = accounts;
        this.idempotency = idempotency;
    }

    @Override
    public TransferResult transfer(TransferCommand command) {
        var previous = idempotency.find(command.idempotencyKey());
        if (previous.isPresent()) {
            return previous.get();
        }

        Account from = load(command.from()).debit(command.amount());
        Account to = load(command.to()).credit(command.amount());

        accounts.save(from);
        accounts.save(to);

        var result = new TransferResult(UUID.randomUUID().toString(), from.balance(), to.balance());
        idempotency.remember(command.idempotencyKey(), result);
        return result;
    }

    private Account load(AccountId id) {
        return accounts.findById(id).orElseThrow(() -> new AccountNotFoundException(id));
    }
}
