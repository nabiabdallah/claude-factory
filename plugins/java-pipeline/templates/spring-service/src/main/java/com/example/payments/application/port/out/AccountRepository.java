package com.example.payments.application.port.out;

import com.example.payments.domain.Account;
import com.example.payments.domain.AccountId;
import java.util.Optional;

public interface AccountRepository {

    Optional<Account> findById(AccountId id);

    void save(Account account);
}
