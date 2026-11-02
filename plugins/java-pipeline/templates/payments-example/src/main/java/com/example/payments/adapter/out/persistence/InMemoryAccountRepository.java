package com.example.payments.adapter.out.persistence;

import com.example.payments.application.port.out.AccountRepository;
import com.example.payments.domain.Account;
import com.example.payments.domain.AccountId;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/** Starter adapter. Replace with a JPA/JDBC adapter behind the same port. */
public class InMemoryAccountRepository implements AccountRepository {

    private final Map<AccountId, Account> store = new ConcurrentHashMap<>();

    @Override
    public Optional<Account> findById(AccountId id) {
        return Optional.ofNullable(store.get(id));
    }

    @Override
    public void save(Account account) {
        store.put(account.id(), account);
    }
}
