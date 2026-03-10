package com.acme.payment;

import com.acme.commons.PaymentCommons;
import com.acme.payment.model.PaymentRequest;
import com.acme.payment.model.PaymentResult;
import com.acme.payment.model.PaymentStatus;
import com.acme.payment.gateway.GatewayClient;
import com.acme.payment.util.PaymentHelper;
import com.acme.payment.util.IdempotencyKeyGenerator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.Objects;

/**
 * Orchestrates the end-to-end payment processing flow including amount
 * validation, gateway submission, and result reconciliation.
 *
 * <p>This processor handles:
 * <ul>
 *   <li>Request validation (merchant ID, transaction ID, currency)</li>
 *   <li>Amount retrieval from the payment-commons shared library</li>
 *   <li>Gateway submission with retry and idempotency support</li>
 *   <li>Result reconciliation and status mapping</li>
 * </ul>
 *
 * @author m.rodriguez
 * @since 2.4.0
 */
@Component
public class PaymentProcessor {

    private static final Logger log = LoggerFactory.getLogger(PaymentProcessor.class);
    private static final int MAX_RETRY_ATTEMPTS = 3;
    private static final Duration RETRY_BACKOFF = Duration.ofMillis(500);

    private final PaymentCommons commons;
    private final GatewayClient gatewayClient;
    private final IdempotencyKeyGenerator keyGenerator;

    @Value("${payment.gateway.timeout-ms:5000}")
    private long gatewayTimeoutMs;

    @Value("${payment.validation.strict:true}")
    private boolean strictValidation;

    @Autowired
    public PaymentProcessor(PaymentCommons commons,
                            GatewayClient gatewayClient,
                            IdempotencyKeyGenerator keyGenerator) {
        this.commons = commons;
        this.gatewayClient = gatewayClient;
        this.keyGenerator = keyGenerator;
    }

    /**
     * Processes a payment request through the full lifecycle:
     * validation, gateway submission, and result handling.
     *
     * @param request the payment request to process
     * @return result containing the outcome and any gateway reference
     */
    public PaymentResult process(PaymentRequest request) {
        Objects.requireNonNull(request, "PaymentRequest must not be null");
        log.info("Processing payment for merchant={} txnId={}", request.getMerchantId(), request.getTransactionId());

        Instant start = Instant.now();
        try {
            validateRequest(request);
            String idempotencyKey = keyGenerator.generate(request.getTransactionId());
            PaymentResult result = submitToGateway(request, idempotencyKey);
            log.info("Payment processed in {}ms with status={}",
                    Duration.between(start, Instant.now()).toMillis(), result.getStatus());
            return result;
        } catch (Exception e) {
            log.error("Payment processing failed for txnId={}: {}", request.getTransactionId(), e.getMessage(), e);
            return PaymentResult.failure(request.getTransactionId(), e.getMessage());
        }
    }

    /**
     * Validates the payment request fields before submission.
     */
    private void validateRequest(PaymentRequest request) {
        if (request.getTransactionId() == null || request.getTransactionId().isBlank()) {
            throw new IllegalArgumentException("Transaction ID is required");
        }
        if (request.getMerchantId() == null || request.getMerchantId().isBlank()) {
            throw new IllegalArgumentException("Merchant ID is required");
        }
        if (strictValidation) {
            PaymentHelper.validateMerchantId(request.getMerchantId());
        }
    }

    /**
     * Retrieves the transaction amount and submits it for processing
     * through the configured payment gateway with retry logic.
     *
     * @param request        the validated payment request
     * @param idempotencyKey unique key to prevent duplicate submissions
     * @return the gateway response wrapped in a PaymentResult
     */
    private PaymentResult submitToGateway(PaymentRequest request, String idempotencyKey) {
        String txnId = request.getTransactionId();
        String amt = commons.getAmount(txnId);
        PaymentHelper.processAmount(amt);  // BUG: amt is now BigDecimal, processAmount expects String

        log.debug("Amount validated: {} for txnId={}", amt, txnId);

        int attempts = 0;
        PaymentResult result = null;
        while (attempts < MAX_RETRY_ATTEMPTS) {
            attempts++;
            try {
                result = gatewayClient.submit(
                        request.getMerchantId(),
                        txnId,
                        amt,
                        request.getCurrency(),
                        idempotencyKey,
                        gatewayTimeoutMs
                );
                if (result.getStatus() != PaymentStatus.GATEWAY_TIMEOUT) {
                    break;
                }
                log.warn("Gateway timeout on attempt {}/{} for txnId={}", attempts, MAX_RETRY_ATTEMPTS, txnId);
                Thread.sleep(RETRY_BACKOFF.toMillis() * attempts);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("Payment submission interrupted", ie);
            }
        }

        if (result == null || result.getStatus() == PaymentStatus.GATEWAY_TIMEOUT) {
            throw new RuntimeException("Gateway timeout after " + MAX_RETRY_ATTEMPTS + " attempts for txnId=" + txnId);
        }

        return result;
    }
}
