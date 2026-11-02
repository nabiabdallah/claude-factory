package com.example.payments.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class MoneyTest {

    @Test
    void scale_follows_currency_minor_units_with_half_even_rounding() {
        assertThat(Money.of("10.125", "EUR").amount()).hasToString("10.12");
        assertThat(Money.of("10.135", "EUR").amount()).hasToString("10.14");
        assertThat(Money.of("10.5", "JPY").amount()).hasToString("10");
    }

    @Test
    void adds_and_subtracts_same_currency() {
        assertThat(Money.of("10.00", "USD").plus(Money.of("2.50", "USD"))).isEqualTo(Money.of("12.50", "USD"));
        assertThat(Money.of("10.00", "USD").minus(Money.of("2.50", "USD"))).isEqualTo(Money.of("7.50", "USD"));
    }

    @Test
    void rejects_arithmetic_across_currencies() {
        assertThatThrownBy(() -> Money.of("1", "USD").plus(Money.of("1", "EUR")))
                .isInstanceOf(CurrencyMismatchException.class);
    }
}
