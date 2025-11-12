#!/bin/bash

# Script para simular un webhook de Stripe manualmente
# SOLO PARA PRUEBAS - Reemplaza los valores reales

ORDER_ID="tu-order-id-aqui"  # ID de la orden que creaste
STRIPE_PAYMENT_ID="ch_test_123456789"
RECEIPT_URL="https://pay.stripe.com/receipts/test/receipt_123"

# Simula el evento payment.succeeded directamente en orders-ms
# Esto bypasea Stripe y va directo a actualizar la orden

echo "Simulando pago exitoso para orden: $ORDER_ID"

# Necesitarías crear un endpoint temporal en orders-ms o
# publicar el evento NATS manualmente
