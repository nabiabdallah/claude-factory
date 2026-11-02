package com.example.payments.domain;

public class InsufficientFundsException extends DomainException {

    public InsufficientFundsException(AccountId accountId) {
        super("Insufficient funds on account " + accountId.masked());
    }
}
