package com.example.payments.adapter.in.web;

import com.example.payments.application.port.in.TransferMoneyUseCase;
import com.example.payments.application.port.in.TransferMoneyUseCase.TransferCommand;
import com.example.payments.domain.AccountId;
import com.example.payments.domain.Money;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/transfers")
public class TransferController {

    private final TransferMoneyUseCase transferMoney;

    public TransferController(TransferMoneyUseCase transferMoney) {
        this.transferMoney = transferMoney;
    }

    @PostMapping
    public TransferResponse transfer(
            @RequestHeader("Idempotency-Key") @NotBlank String idempotencyKey,
            @Valid @RequestBody TransferRequest request) {
        var result = transferMoney.transfer(new TransferCommand(
                idempotencyKey,
                new AccountId(request.fromAccount()),
                new AccountId(request.toAccount()),
                Money.of(request.amount(), request.currency())));
        return new TransferResponse(
                result.transferId(),
                result.fromBalance().amount().toPlainString(),
                result.fromBalance().currency().getCurrencyCode());
    }

    public record TransferRequest(
            @NotBlank String fromAccount,
            @NotBlank String toAccount,

            @NotBlank @Pattern(regexp = "\\d+(\\.\\d{1,4})?")
            String amount,

            @NotBlank @Pattern(regexp = "[A-Z]{3}") String currency) {}

    public record TransferResponse(String transferId, String remainingBalance, String currency) {}
}
