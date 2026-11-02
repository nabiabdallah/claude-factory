package com.example.payments.domain;

public class AccountNotFoundException extends DomainException {

    public AccountNotFoundException(AccountId accountId) {
        super("Account not found: " + accountId.masked());
    }
}
