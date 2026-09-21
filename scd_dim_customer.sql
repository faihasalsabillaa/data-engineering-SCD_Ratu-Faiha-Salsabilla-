-- =====================================================================
-- data engineering - assignment 1
-- lassicmodel cars sales - dim_customer
-- Ratu Faiha Salsabilla Rahmadina
-- 24/532756/PA/22533
-- =====================================================================

USE classicmodels;

-- step 1 — create dimension table

DROP TABLE IF EXISTS dim_customer;

CREATE TABLE dim_customer (
    customer_key INT AUTO_INCREMENT PRIMARY KEY,
    customerNumber INT NOT NULL,
    customerName VARCHAR(50) NOT NULL,
    contactLastName VARCHAR(50),
    contactFirstName VARCHAR(50),
    addressLine1 VARCHAR(50),
    addressLine2 VARCHAR(50),
    city VARCHAR(50),
    state VARCHAR(50),
    postalCode VARCHAR(15),
    country VARCHAR(50),
    salesRepEmployeeNumber INT,
    creditLimit DECIMAL(10,2),
    effective_date DATE NOT NULL,
    expiry_date DATE NOT NULL DEFAULT '9999-12-31',
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    INDEX idx_customer (customerNumber, is_current)
);

-- initial data

INSERT INTO dim_customer
    (customerNumber, customerName, contactLastName, contactFirstName,
     addressLine1, addressLine2, city, state, postalCode, country,
     salesRepEmployeeNumber, creditLimit,
     effective_date, expiry_date, is_current)
SELECT
    customerNumber, customerName, contactLastName, contactFirstName,
    addressLine1, addressLine2, city, state, postalCode, country,
    salesRepEmployeeNumber, creditLimit,
    '1900-01-01', '9999-12-31', TRUE
FROM customers;

-- step 2 — SCD procedure

DROP PROCEDURE IF EXISTS upsert_dim_customer;

DELIMITER $$

CREATE PROCEDURE upsert_dim_customer(
    IN p_customerNumber INT,
    IN p_customerName VARCHAR(50),
    IN p_contactLastName VARCHAR(50),
    IN p_contactFirstName VARCHAR(50),
    IN p_addressLine1 VARCHAR(50),
    IN p_addressLine2 VARCHAR(50),
    IN p_city VARCHAR(50),
    IN p_state VARCHAR(50),
    IN p_postalCode VARCHAR(15),
    IN p_country VARCHAR(50),
    IN p_salesRepEmployeeNumber INT,
    IN p_creditLimit DECIMAL(10,2),
    IN p_effective_date DATE
)
BEGIN
    DECLARE v_customer_key INT;
    DECLARE v_addressLine1 VARCHAR(50);
    DECLARE v_addressLine2 VARCHAR(50);
    DECLARE v_city VARCHAR(50);
    DECLARE v_state VARCHAR(50);
    DECLARE v_postalCode VARCHAR(15);
    DECLARE v_country VARCHAR(50);
    DECLARE v_salesRepEmployeeNumber INT;
    DECLARE v_creditLimit DECIMAL(10,2);

    SELECT customer_key, addressLine1, addressLine2, city, state,
           postalCode, country, salesRepEmployeeNumber, creditLimit
    INTO v_customer_key, v_addressLine1, v_addressLine2, v_city, v_state,
         v_postalCode, v_country, v_salesRepEmployeeNumber, v_creditLimit
    FROM dim_customer
    WHERE customerNumber = p_customerNumber
      AND is_current = TRUE
    LIMIT 1;

    IF v_customer_key IS NULL THEN

        INSERT INTO dim_customer
            (customerNumber, customerName, contactLastName, contactFirstName,
             addressLine1, addressLine2, city, state, postalCode, country,
             salesRepEmployeeNumber, creditLimit,
             effective_date, expiry_date, is_current)
        VALUES
            (p_customerNumber, p_customerName, p_contactLastName,
             p_contactFirstName, p_addressLine1, p_addressLine2,
             p_city, p_state, p_postalCode, p_country,
             p_salesRepEmployeeNumber, p_creditLimit,
             p_effective_date, '9999-12-31', TRUE);

    ELSEIF v_addressLine1 <=> p_addressLine1
       AND v_addressLine2 <=> p_addressLine2
       AND v_city <=> p_city
       AND v_state <=> p_state
       AND v_postalCode <=> p_postalCode
       AND v_country <=> p_country
       AND v_salesRepEmployeeNumber <=> p_salesRepEmployeeNumber
       AND v_creditLimit <=> p_creditLimit THEN

        UPDATE dim_customer
        SET customerName = p_customerName,
            contactLastName = p_contactLastName,
            contactFirstName = p_contactFirstName
        WHERE customer_key = v_customer_key;

    ELSE

        UPDATE dim_customer
        SET expiry_date = DATE_SUB(p_effective_date, INTERVAL 1 DAY),
            is_current = FALSE
        WHERE customer_key = v_customer_key;

        INSERT INTO dim_customer
            (customerNumber, customerName, contactLastName, contactFirstName,
             addressLine1, addressLine2, city, state, postalCode, country,
             salesRepEmployeeNumber, creditLimit,
             effective_date, expiry_date, is_current)
        VALUES
            (p_customerNumber, p_customerName, p_contactLastName,
             p_contactFirstName, p_addressLine1, p_addressLine2,
             p_city, p_state, p_postalCode, p_country,
             p_salesRepEmployeeNumber, p_creditLimit,
             p_effective_date, '9999-12-31', TRUE);

    END IF;
END$$

DELIMITER ;

-- step 3 — test type 2 change
-- customer 119: La Rochelle Gifts
-- sales rep changes from 1370 to 1337

SELECT *
FROM dim_customer
WHERE customerNumber = 119
  AND is_current = TRUE;

CALL upsert_dim_customer(
    119,
    'La Rochelle Gifts',
    'Labrune',
    'Janine',
    '67, rue des Cinquante Otages',
    NULL,
    'Nantes',
    NULL,
    '44000',
    'France',
    1337,
    118200.00,
    '2005-06-01'
);

SELECT customer_key, customerNumber, salesRepEmployeeNumber,
       creditLimit, effective_date, expiry_date, is_current
FROM dim_customer
WHERE customerNumber = 119
ORDER BY effective_date;

-- idempotency test

CALL upsert_dim_customer(
    119,
    'La Rochelle Gifts',
    'Labrune',
    'Janine',
    '67, rue des Cinquante Otages',
    NULL,
    'Nantes',
    NULL,
    '44000',
    'France',
    1337,
    118200.00,
    '2005-06-15'
);

SELECT COUNT(*) AS row_count
FROM dim_customer
WHERE customerNumber = 119;

-- step 4 — point-in-time query

SELECT
    YEAR(o.orderDate) AS order_year,
    dc.salesRepEmployeeNumber,
    SUM(od.quantityOrdered * od.priceEach) AS total_order_value
FROM orders o
JOIN orderdetails od
    ON o.orderNumber = od.orderNumber
JOIN dim_customer dc
    ON o.customerNumber = dc.customerNumber
   AND o.orderDate BETWEEN dc.effective_date AND dc.expiry_date
WHERE o.status <> 'Cancelled'
GROUP BY YEAR(o.orderDate), dc.salesRepEmployeeNumber
ORDER BY order_year, total_order_value DESC;