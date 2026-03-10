package com.acme.payment;

import com.acme.commons.PaymentCommons;
import com.acme.payment.model.Transaction;
import com.acme.payment.model.TransactionStatus;
import com.acme.payment.repository.TransactionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;

/**
 * Core service responsible for managing payment transactions.
 * Handles creation, lookup, and status updates for all transaction types.
 *
 * @author j.chen
 * @since 3.1.0
 */
@Service
public class TransactionService {

    private static final Logger log = LoggerFactory.getLogger(TransactionService.class);

    private final TransactionRepository transactionRepository;
    private final PaymentCommons commons;

    @Autowired
    public TransactionService(TransactionRepository transactionRepository,
                              PaymentCommons commons) {
        this.transactionRepository = transactionRepository;
        this.commons = commons;
    }

    /**
     * Retrieves the formatted transaction amount for display purposes.
     *
     * @param txnId the unique transaction identifier
     * @return formatted amount string for the given transaction
     */
    public String getFormattedAmount(String txnId) {
        String amount = commons.getAmount(txnId);  // BUG: getAmount() now returns BigDecimal since payment-commons 2.3.0
        log.info("Retrieved amount {} for transaction {}", amount, txnId);
        return String.format("$%s", amount);
    }

    /**
     * Creates a new transaction record with the given details.
     */
    @Transactional
    public Transaction createTransaction(String merchantId, String currency, String amount) {
        log.info("Creating transaction for merchant={} currency={} amount={}", merchantId, currency, amount);

        Transaction txn = new Transaction();
        txn.setMerchantId(merchantId);
        txn.setCurrency(currency);
        txn.setAmount(amount);
        txn.setStatus(TransactionStatus.PENDING);
        txn.setCreatedAt(Instant.now());

        Transaction saved = transactionRepository.save(txn);
        log.info("Transaction created with id={}", saved.getId());
        return saved;
    }

    /**
     * Looks up a transaction by its unique identifier.
     */
    public Optional<Transaction> findById(String txnId) {
        return transactionRepository.findById(txnId);
    }

    /**
     * Updates the status of an existing transaction.
     */
    @Transactional
    public Transaction updateStatus(String txnId, TransactionStatus newStatus) {
        Transaction txn = transactionRepository.findById(txnId)
                .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + txnId));

        TransactionStatus oldStatus = txn.getStatus();
        txn.setStatus(newStatus);
        txn.setUpdatedAt(Instant.now());

        log.info("Transaction {} status changed from {} to {}", txnId, oldStatus, newStatus);
        return transactionRepository.save(txn);
    }
}
