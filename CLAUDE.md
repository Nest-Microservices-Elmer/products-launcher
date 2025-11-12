# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Arquitectura del Proyecto

Este es un sistema de microservicios NestJS que utiliza **Git Submodules** para gestionar cada microservicio de forma independiente. La arquitectura sigue un patrón de API Gateway con comunicación basada en eventos usando NATS.

### Microservicios

- **client-gateway**: Gateway principal que expone la API REST al cliente (puerto 3000)
- **auth-ms**: Microservicio de autenticación con JWT (MongoDB)
- **products-ms**: Microservicio de productos (Prisma + SQLite)
- **orders-ms**: Microservicio de órdenes (Prisma + PostgreSQL)
- **payments-ms**: Microservicio de pagos con Stripe (puerto 3003)
- **nats-server**: Servidor NATS para mensajería entre microservicios

### Comunicación

Todos los microservicios se comunican vía **NATS** (puerto 4222, monitoreo en 8222). El client-gateway recibe peticiones HTTP REST y las traduce a mensajes NATS hacia los microservicios correspondientes.

El módulo `NatsModule` en client-gateway registra el cliente NATS que se inyecta en los controladores para enviar mensajes. Los microservicios escuchan patrones específicos de NATS y responden.

## Comandos de Desarrollo

### Configuración Inicial

```bash
# 1. Clonar el repositorio
git clone <repo-url>

# 2. Inicializar y actualizar submodules
git submodule update --init --recursive

# 3. Crear archivo .env basado en .env.template
cp .env.template .env
# Editar .env con las credenciales necesarias (Stripe, MongoDB, etc.)

# 4. Levantar todos los servicios en modo desarrollo
docker compose up --build
```

**NOTA IMPORTANTE:** Para que el sistema de pagos funcione completamente, debes configurar webhooks de Stripe (ver sección "Configuración de Webhooks de Stripe" más abajo). Sin esto, las órdenes se quedarán en estado PENDING después de pagar.

### Desarrollo Local

```bash
# Levantar servicios en desarrollo (con hot-reload)
docker compose up

# Reconstruir imágenes después de cambios en dependencias
docker compose up --build

# Ver logs de un servicio específico
docker compose logs -f <service-name>

# Detener todos los servicios
docker compose down
```

### Configuración de Webhooks de Stripe (CRÍTICO para payments-ms)

**IMPORTANTE:** El microservicio de pagos depende de webhooks de Stripe para actualizar el estado de las órdenes de `PENDING` a `PAID`. En desarrollo local, Stripe NO puede enviar webhooks directamente a `localhost`, por lo que se requiere un túnel.

#### Opciones para Recibir Webhooks en Desarrollo

**Opción 1: Hookdeck CLI (Recomendado)**

Si ya tienes Hookdeck configurado:

```bash
# Terminal separada - debe estar corriendo SIEMPRE durante desarrollo
hookdeck listen
```

Configurar `STRIPE_ENDPOINT_SECRET` en `.env` con el secret que proporciona Hookdeck.

**Opción 2: Stripe CLI**

```bash
# 1. Login (solo primera vez)
stripe login

# 2. Escuchar webhooks (terminal separada - mantener corriendo)
stripe listen --forward-to localhost:3003/payments/webhook
```

Esto mostrará un webhook signing secret como:
```
Ready! Your webhook signing secret is whsec_xxxxxxxxxxxxx
```

Actualizar `.env`:
```bash
STRIPE_ENDPOINT_SECRET=whsec_xxxxxxxxxxxxx
```

Reiniciar payments-ms:
```bash
docker compose restart payments-ms
```

**Opción 3: ngrok**

```bash
# Exponer puerto 3003
ngrok http 3003
```

Configurar el webhook en Stripe Dashboard apuntando a la URL de ngrok.

#### Flujo de Pagos Completo

```
1. Cliente crea orden → Status: PENDING
2. Se genera checkout session de Stripe
3. Usuario paga en Stripe
4. Stripe envía webhook → Hookdeck/Stripe CLI/ngrok
5. Webhook llega a payments-ms (localhost:3003/payments/webhook)
6. payments-ms emite evento NATS "payment.succeeded"
7. orders-ms actualiza Order en PostgreSQL:
   - status: PENDING → PAID
   - paid: false → true
   - paidAt: timestamp
   - stripeChargeId: ID del cargo
8. Se crea OrderReceipt con receiptUrl
```

#### Verificar que Webhooks Funcionan

```bash
# Verificar órdenes en base de datos
docker exec orders_database psql -U postgres -d ordersdb \
  -c "SELECT id, status, paid, \"paidAt\" FROM \"Order\" ORDER BY \"createdAt\" DESC LIMIT 5;"

# Verificar recibos creados
docker exec orders_database psql -U postgres -d ordersdb \
  -c "SELECT * FROM \"OrderReceipt\";"

# Ver logs de webhooks
docker compose logs payments-ms | grep -i webhook
docker compose logs orders-ms | grep -i paid
```

**SIN el túnel de webhooks activo, las órdenes se quedarán permanentemente en estado PENDING.**

### Testing

Cada microservicio (submodule) tiene sus propios tests:

```bash
# Ejecutar tests unitarios en un microservicio
cd <microservice-dir>
npm run test

# Tests en modo watch
npm run test:watch

# Tests con coverage
npm run test:cov

# Tests e2e
npm run test:e2e
```

### Linting y Formato

```bash
# Lint con auto-fix
npm run lint

# Formatear código
npm run format
```

### Base de Datos (Prisma)

Los microservicios products-ms y orders-ms usan Prisma:

```bash
# Generar cliente Prisma
prisma generate

# Ejecutar migraciones
prisma migrate dev

# Ver base de datos (solo en desarrollo)
prisma studio
```

## Producción

### Docker Compose (Producción)

```bash
# Build de imágenes de producción
docker compose -f docker-compose.prod.yml build

# Las imágenes se suben a Google Cloud Artifact Registry:
# northamerica-northeast1-docker.pkg.dev/tienda-microservices/image-registry/
```

### Kubernetes / Helm

El directorio `k8s/tienda` contiene la configuración de Helm Chart.

```bash
# Instalar configuración inicial
helm install tienda k8s/tienda

# Aplicar actualizaciones
helm upgrade tienda k8s/tienda

# Comandos útiles de kubectl
kubectl get pods
kubectl get deployments
kubectl get services
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl delete pod <pod-name>
```

Consultar `K8s.README.md` para información detallada sobre:
- Creación de deployments y services
- Gestión de secrets
- Configuración de Google Cloud Registry
- Comandos de kubectl y helm

## Gestión de Git Submodules

### Flujo de Trabajo CRÍTICO

**SIEMPRE seguir este orden al hacer cambios:**

1. Hacer cambios en el submodule
2. Commit y push en el submodule
3. Luego commit y push en el repositorio principal

**Nunca al revés**, o se perderán las referencias de los submodules.

### Comandos Útiles

```bash
# Actualizar referencias de submodules al último commit
git submodule update --remote

# Clonar repo con todos los submodules
git clone --recursive <repo-url>

# Si ya clonaste sin --recursive
git submodule update --init --recursive

# Ver estado de todos los submodules
git submodule status
```

## Estructura de Código NestJS

### Client Gateway

- `src/main.ts`: Configuración global con ValidationPipe y prefijo `/api`
- `src/transports/nats.module.ts`: Módulo compartido para cliente NATS
- `src/common`: Filtros de excepción RPC y decoradores compartidos
- `src/config`: Variables de entorno usando Joi
- Módulos por dominio: `auth/`, `products/`, `orders/`

### Microservicios

Cada microservicio sigue estructura similar:
- `src/main.ts`: Bootstrap con transporte NATS
- Módulos de dominio con controllers, services, DTOs
- `src/config`: Validación de variables de entorno

### Validación

Todos los DTOs usan `class-validator` y `class-transformer`. El gateway tiene configurado globalmente:

```typescript
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
  })
);
```

## Variables de Entorno

Archivo `.env.template` muestra las variables necesarias:

```
CLIENT_GATEWAY_PORT=3000
PAYMENTS_MS_PORT=3003
STRIPE_SECRET=                    # API Key de Stripe (dashboard)
STRIPE_SUCCESS_URL=               # URL de redirección después de pago exitoso
STRIPE_CANCEL_URL=                # URL de redirección si cancela el pago
STRIPE_ENDPOINT_SECRET=           # Webhook signing secret (ver sección de Webhooks)
AUTH_DATABASE_URL=mongodb+srv://...
JWT_SECRET=
ORDERS_DATABASE_URL=postgresql://...
```

### Configuración de STRIPE_ENDPOINT_SECRET

Este valor es **diferente según el entorno**:

- **Desarrollo local:** Usar el secret que proporciona Hookdeck CLI o Stripe CLI (`whsec_...`)
- **Producción:** Usar el secret del webhook configurado en Stripe Dashboard

**NUNCA usar el mismo secret para desarrollo y producción.**

## Notas de Seguridad

- JWT_SECRET debe ser una cadena segura en producción
- Secrets de Stripe y MongoDB deben estar en variables de entorno
- En Kubernetes, usar `kubectl create secret` para credenciales
- No commitear archivo `.env` (está en .gitignore)

## Troubleshooting Común

### Problema: Las órdenes se quedan en PENDING después de pagar

**Síntomas:**
- El pago en Stripe es exitoso
- La orden en la base de datos tiene `status: PENDING` y `paid: false`
- No se crea el registro en `OrderReceipt`

**Causa:** Los webhooks de Stripe no están llegando a payments-ms

**Solución:**

1. Verificar que Hookdeck CLI o Stripe CLI esté corriendo:
   ```bash
   # Debe estar activo en una terminal separada
   hookdeck listen
   # O
   stripe listen --forward-to localhost:3003/payments/webhook
   ```

2. Verificar que `STRIPE_ENDPOINT_SECRET` en `.env` coincida con el secret del CLI

3. Reiniciar payments-ms después de cambiar el secret:
   ```bash
   docker compose restart payments-ms
   ```

4. Verificar logs para confirmar que el webhook llega:
   ```bash
   docker compose logs payments-ms -f
   ```

### Problema: Error "Empty response. There are no subscribers listening to that message"

**Causa:** El microservicio de destino no está corriendo o no se conectó a NATS

**Solución:**
1. Verificar que todos los servicios estén running:
   ```bash
   docker compose ps
   ```

2. Verificar logs del servicio que falla:
   ```bash
   docker compose logs <service-name>
   ```

3. Verificar que NATS server esté corriendo:
   ```bash
   docker compose logs nats-server
   ```

### Problema: Variables de entorno no se actualizan

**Solución:**
Después de modificar `.env`, siempre reiniciar el servicio afectado:
```bash
docker compose restart <service-name>
# O reiniciar todos
docker compose down && docker compose up -d
```
