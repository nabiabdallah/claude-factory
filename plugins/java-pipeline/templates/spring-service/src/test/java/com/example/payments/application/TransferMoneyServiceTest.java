package com.example.payments.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.example.payments.adapter.out.persistence.InMemoryAccountRepository;
import com.example.payments.adapter.out.persistence.InMemoryIdempotencyStore;
import com.example.payments.application.port.in.TransferMoneyUseCase.TransferCommand;
import com.example.payments.domain.Account;
import com.example.payments.domain.AccountId;
import com.example.payments.domain.AccountNotFoundException;
import com.example.payments.domain.CurrencyMismatchException;
import com.example.payments.domain.InsufficientFundsException;
import com.example.payments.domain.InvalidAmountException;
import com.example.payments.domain.Money;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class TransferMoneyServiceTest {

    private static final AccountId ALICE = new AccountId("LB00ALICE0001");
    private static final AccountId BOB = new AccountId("LB00BOB000002");

    private InMemoryAccountRepository accounts;
    private TransferMoneyService service;

    @BeforeEach
    void setUp() {
        accounts = new InMemoryAccountRepository();
        accounts.save(new Account(ALICE, Money.of("100.00", "USD")));
        accounts.save(new Account(BOB, Money.of("5.00", "USD")));
        service = new TransferMoneyService(accounts, new InMemoryIdempotencyStore());
    }

    @Test
    void moves_money_between_accounts() {
        var result = service.transfer(command("k1", "30.00"));

        assertThat(result.fromBalance()).isEqualTo(Money.of("70.00", "USD"));
        assertThat(result.toBalance()).isEqualTo(Money.of("35.00", "USD"));
        assertThat(accounts.findById(ALICE)).get().extracting(Account::balance).isEqualTo(Money.of("70.00", "USD"));
    }

    @Test
    void fails_and_changes_nothing_when_funds_are_insufficient() {
        assertThatThrownBy(() -> service.transfer(command("k1", "100.01")))
                .isInstanceOf(InsufficientFundsException.class)
                .hasMessageNotContaining("LB00ALICE0001");

        assertThat(accounts.findById(ALICE)).get().extracting(Account::balance).isEqualTo(Money.of("100.00", "USD"));
        assertThat(accounts.findById(BOB)).get().extracting(Account::balance).isEqualTo(Money.of("5.00", "USD"));
    }

    @Test
    void repeating_an_idempotency_key_does_not_move_money_twice() {
        var first = service.transfer(command("same-key", "10.00"));
        var second = service.transfer(command("same-key", "10.00"));

        assertThat(second).isEqualTo(first);
        assertThat(accounts.findById(ALICE)).get().extracting(Account::balance).isEqualTo(Money.of("90.00", "USD"));
    }

    @Test
    void rejects_zero_amount() {
        assertThatThrownBy(() -> service.transfer(command("k1", "0.00"))).isInstanceOf(InvalidAmountException.class);
    }

    @Test
    void rejects_currency_mismatch() {
        var eur = new TransferCommand("k1", ALICE, BOB, Money.of("1.00", "EUR"));
        assertThatThrownBy(() -> service.transfer(eur)).isInstanceOf(CurrencyMismatchException.class);
    }

    @Test
    void rejects_unknown_account() {
        var unknown = new TransferCommand("k1", ALICE, new AccountId("LB00NOBODY999"), Money.of("1.00", "USD"));
        assertThatThrownBy(() -> service.transfer(unknown)).isInstanceOf(AccountNotFoundException.class);
    }

    private static TransferCommand command(String key, String amount) {
        return new TransferCommand(key, ALICE, BOB, Money.of(amount, "USD"));
    }
}
