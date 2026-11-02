package com.example.payments.config;

import com.example.payments.adapter.out.persistence.InMemoryAccountRepository;
import com.example.payments.adapter.out.persistence.InMemoryIdempotencyStore;
import com.example.payments.application.TransferMoneyService;
import com.example.payments.application.port.in.TransferMoneyUseCase;
import com.example.payments.application.port.out.AccountRepository;
import com.example.payments.application.port.out.IdempotencyStore;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** The only place that knows which adapter implements which port. */
@Configuration
public class PaymentsConfig {

    @Bean
    AccountRepository accountRepository() {
        return new InMemoryAccountRepository();
    }

    @Bean
    IdempotencyStore idempotencyStore() {
        return new InMemoryIdempotencyStore();
    }

    @Bean
    TransferMoneyUseCase transferMoneyUseCase(AccountRepository accounts, IdempotencyStore idempotency) {
        return new TransferMoneyService(accounts, idempotency);
    }
}
