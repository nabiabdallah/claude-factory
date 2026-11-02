package com.example.payments.domain;

import java.util.Objects;

public record AccountId(String value) {

    public AccountId {
        Objects.requireNonNull(value, "value");
        if (value.isBlank()) {
            throw new IllegalArgumentException("AccountId must not be blank");
        }
    }

    /** Masked form for logs and error messages — never log the full identifier. */
    public String masked() {
        int keep = Math.min(4, value.length());
        return "****" + value.substring(value.length() - keep);
    }

    @Override
    public String toString() {
        return masked();
    }
}
