package com.example.payments.domain;

/** Base type for business-rule violations. The web adapter maps these to 4xx responses. */
public abstract class DomainException extends RuntimeException {

    protected DomainException(String message) {
        super(message);
    }
}
