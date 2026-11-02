package com.example.payments.domain;

public class InvalidAmountException extends DomainException {

    public InvalidAmountException(String message) {
        super(message);
    }
}
