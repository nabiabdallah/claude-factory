package com.example.payments.domain;

import java.util.Objects;

/** A ledger account. Mutations return a new instance; persistence is the adapter's concern. */
public record Account(AccountId id, Money balance) {

    public Account {
        Objects.requireNonNull(id, "id");
        Objects.requireNonNull(balance, "balance");
    }

    public Account debit(Money amount) {
        requirePositive(amount);
        if (balance.isLessThan(amount)) {
            throw new InsufficientFundsException(id);
        }
        return new Account(id, balance.minus(amount));
    }

    public Account credit(Money amount) {
        requirePositive(amount);
        return new Account(id, balance.plus(amount));
    }

    private static void requirePositive(Money amount) {
        if (!amount.isPositive()) {
            throw new InvalidAmountException("Amount must be positive");
        }
    }
}
