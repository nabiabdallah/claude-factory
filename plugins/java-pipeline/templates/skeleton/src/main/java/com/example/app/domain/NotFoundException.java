package com.example.app.domain;

/** A requested entity does not exist. Subclass per entity, e.g. {@code CustomerNotFoundException}. */
public abstract class NotFoundException extends DomainException {

    protected NotFoundException(String message) {
        super(message);
    }
}
