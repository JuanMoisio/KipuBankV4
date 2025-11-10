# KipuBank V3

Banco cripto educativo con depósitos en **ETH** y **ERC-20**, acreditación interna en **USDC** (unidad contable), soporte nativo para **KGLD**, swaps vía **Uniswap V2** y tope de pasivos USD con **Chainlink**. Construido con **Solidity (0.8.x)** y **Foundry**.

---

## ✨ Mejoras principales (y por qué)

1. **Depósitos genéricos → USDC**  
   - `depositNative(minUsdcOut, deadline)`: ETH → USDC vía Uniswap V2.  
   - `depositAnyToken(tokenIn, amountIn, minUsdcOut, deadline)`: ruta `[tokenIn, USDC]` o fallback `[tokenIn, WETH, USDC]`.  
   **Motivo**: simplificar UX y estandarizar contabilidad interna.

2. **Soporte nativo de KGLD**  
   - `depositERC20(KGLD, amount)`: acredita KGLD interno (sin swap).  
   **Motivo**: escenarios educativos con token propio.

3. **Límites y contabilidad de riesgo**  
   - `WITHDRAW_MAX`: tope por retiro de ETH.  
   - `BANKCAP`: tope global de depósitos.  
   - `BANK_USD_CAP8` (8 dec) con **Chainlink ETH/USD**: tope de pasivos USD para depósitos de ETH.  
   **Motivo**: modelar exposición y evitar exceso de pasivos.

4. **Seguridad operativa**  
   - `Pausable` para detener operaciones.  
   - Guardas anti-reentrancia propias (`_locked`).  
   **Motivo**: defensa ante incidentes y patrones seguros.

5. **Suite de tests (Foundry)**  
   - Fixtures que montan liquidez WETH/USDC localmente.  
   - Casos felices/errores (slippage, sin liquidez, tokens no permitidos).  
   **Motivo**: reproducibilidad y confianza en cambios.

---

## 🚀 Despliegue

### Requisitos
- **Foundry** (`forge`, `cast`)
- RPC (local o remota)
- Cuenta con ETH de gas (testnet)

### Variables de entorno

Creá `.env` y cargalo con `set -a; source .env; set +a`.

```env
# Local (anvil)
ETH_RPC_URL=http://127.0.0.1:8545
ETH_PRIVATE_KEY=0x<clave_anvil_0>
OWNER=0x<anvil_0>
ROUTER=<addr_router_uniswap_v2_local>   # si usás router local

# Sepolia
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/<project_id>
PRIVATE_KEY=0x<pk_deploy>
OWNER=0x<tu_address>
ROUTER=0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3           # UniswapV2Router02
FEED_ETH_USD=0x694AA1769357215DE4FAC081bf1f309aDC325306     # Chainlink ETH/USD
USDC_SEPOLIA=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238     # USDC de Sepolia que usamos

# Opcional (script puede agregar liquidez WETH/USDC si tenés USDC reales)
ADD_LIQUIDITY=0
LIQ_USDC_AMOUNT=100000000             # 100 USDC (6 dec)
LIQ_ETH_AMOUNT_WEI=10000000000000000  # 0.01 ETH
```

### Local (anvil + router V2)
Los tests/fixtures crean liquidez en `setUp()`, no dependés de estado previo.  
Si querés interactuar manualmente, asegurate de tener router V2 y WETH locales.

### Sepolia (deploy único)

Script: `script/DeployAllSepolia.s.sol:DeployAllSepolia`  
— Despliega **KGLD** (mock 18d) y **KipuBank**.  
— (Opcional) Agrega liquidez WETH/USDC.

```bash
forge script script/DeployAllSepolia.s.sol:DeployAllSepolia   --rpc-url "$SEPOLIA_RPC_URL"   --private-key "$PRIVATE_KEY"   --broadcast --skip-simulation -vv
```

Al final imprime: `KGLD`, `BANK`, `USDC`, `WETH`, `ROUTER`, `FEED`.

---

## 🔗 Verificación en Etherscan

Exportá tu API key:
```bash
export ETHERSCAN_API_KEY=<tu_api_key>
```

**KipuBank** (con constructor):
```bash
forge verify-contract <BANK_ADDR> src/KipuBank.sol:KipuBank   --chain sepolia   --constructor-args $(cast abi-encode     "constructor(address,uint256,uint256,address,uint256,address,address,address)"     $OWNER 1000000000000000000000 10000000000000000000     $FEED_ETH_USD 0 $USDC_SEPOLIA <KGLD_ADDR> $ROUTER)   --watch
```

**KGLD** (mock del script):
```bash
forge verify-contract <KGLD_ADDR> script/DeployAllSepolia.s.sol:KGLD18   --chain sepolia --watch
```

> Si preferís un KGLD “formal” en `src/`, incluí `src/KipuGLD.sol`, deploy con `forge create` y verificá con `constructor(address owner)`.

---

## 🧪 Tests y cobertura

Ejecutar:
```bash
forge test -vvv
```

Cobertura:
```bash
forge coverage --report summary
# opcional:
forge coverage --report lcov
genhtml lcov.info --branch-coverage --output-dir coverage
open coverage/index.html
```

### Tests incluidos
- **`test/KipuBank.Native.t.sol`**  
  Fixture (USDC/KGLD/MockV3 + WETH/USDC), deploy del banco.  
  `depositNative` feliz (evento + crédito USDC) y “sin liquidez” (revert).
- **`test/KipuBank.DepositAny.t.sol`**  
  `depositAnyToken` USDC directo (1:1) y genérico MOCK→WETH→USDC (slippage 1%).

Próximos:
- **`Withdraw.t.sol`**: retiros USDC/KGLD/ETH, WITHDRAW_MAX, pausas, caps USD.
- **Fuzz/invariantes**: sumas de saldos internos vs balances on-chain, no superar caps, etc.

---

## 🕹️ Interacción (CLI de ejemplo)

**Depósito nativo (ETH→USDC interno)**:
```bash
DEADLINE=$(( $(date +%s) + 3600 ))
cast send $BANK "depositNative(uint256,uint256)" 1 $DEADLINE   --value 10000000000000000   --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"

# consultar crédito interno
cast call $BANK "erc20Balances(address,address)(uint256)" $USDC_SEPOLIA $OWNER   --rpc-url "$SEPOLIA_RPC_URL"
```

**Depósito ERC-20 genérico**:
```bash
# approve al banco
cast send $TOKEN "approve(address,uint256)" $BANK   0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff   --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"

# calcular minOut con getAmountsOut (router) y ejecutar:
cast send $BANK "depositAnyToken(address,uint256,uint256,uint256)"   $TOKEN <amountIn> <minUsdcOut> $DEADLINE   --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

**Retiros**:
```bash
# USDC/KGLD
cast send $BANK "withdrawalERC20(address,uint256)" $USDC_SEPOLIA <amount>   --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"

# ETH (respeta WITHDRAW_MAX)
cast send $BANK "withdrawal(uint256)" <ethWei>   --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

**Operativa**:
```bash
cast call $BANK "owner()(address)" --rpc-url "$SEPOLIA_RPC_URL"
cast send $BANK "pause()"   --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send $BANK "unpause()" --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
```

---

## 🧩 Decisiones de diseño y trade-offs

- **USDC como unidad contable**  
  ✅ contabilidad simple; UX clara  
  ⚠️ dependencia de liquidez y slippage en Uniswap

- **Rutas directas o vía WETH**  
  ✅ mejor conectividad de pares  
  ⚠️ mayor gas/variabilidad en rutas largas

- **Cap USD con Chainlink**  
  ✅ control de pasivos en unidad estable  
  ⚠️ dependencia de oráculo; alcance inicial enfocado a depósitos de ETH

- **Pausable + no-reentrancia**  
  ✅ seguridad operativa  
  ⚠️ más estados a considerar en tests / operativa

- **Mocks y scripts parametrizables**  
  ✅ reproducibilidad local y despliegue en testnet sin tocar contratos  
  ⚠️ gestión de direcciones/envs; evitar “direcciones viejas” (solución: `.env` y logs de `broadcast/`)

- **Slippage fijo 1% (tests)**  
  ✅ simple y pedagógico  
  ⚠️ en producción podría ser input del usuario o dinámico por volatilidad

---

## 🛠️ Estructura del repo (sugerida)

```
src/
  KipuBank.sol
  interfaces/ (IUniswapV2Router02.sol, etc.)
  tokens/ (opcional: KipuGLD.sol)
script/
  DeployAllSepolia.s.sol
test/
  KipuBank.Native.t.sol
  KipuBank.DepositAny.t.sol
foundry.toml
README.md
.env.example
```

---

## 🧯 Troubleshooting

- **“Unable to locate ContractCode”**: revisá que estés en **Sepolia** (no mainnet). `cast code <addr>` debe devolver bytecode.  
- **`--fork-url` requerido**: usá `--skip-simulation` o pasá `--fork-url "$SEPOLIA_RPC_URL"` en `forge script`.  
- **Verificación falla**: alinear `solc_version`/optimizer con `foundry.toml`.  
- **Swaps revierten**: falta liquidez o ruta → creá pools o ajustá `minUsdcOut`.  
- **Direcciones viejas**: cada sesión de anvil cambia addresses → usar logs de `broadcast/*/run-latest.json` o `.env`.


## 📊 Cobertura y estadísticas de tests

Los tests están escritos con **Foundry** (`forge-std/Test.sol`) y cubren depósitos nativos, depósitos ERC‑20 (directo y vía WETH), eventos, y casos de error por falta de liquidez/slippage.

╭--------------------------------+------------------+------------------+----------------+-----------------╮
| File                           | % Lines          | % Statements     | % Branches     | % Funcs         |
+=========================================================================================================+
| script/Deploy.s.sol            | 0.00% (0/15)     | 0.00% (0/24)     | 0.00% (0/1)    | 0.00% (0/1)     |
|--------------------------------+------------------+------------------+----------------+-----------------|
| script/DeployAllSepolia.s.sol  | 0.00% (0/48)     | 0.00% (0/60)     | 0.00% (0/5)    | 0.00% (0/4)     |
|--------------------------------+------------------+------------------+----------------+-----------------|
| script/DeployKGLD.s.sol        | 0.00% (0/8)      | 0.00% (0/11)     | 100.00% (0/0)  | 0.00% (0/1)     |
|--------------------------------+------------------+------------------+----------------+-----------------|
| script/DeployMockV3.s.sol      | 0.00% (0/7)      | 0.00% (0/8)      | 100.00% (0/0)  | 0.00% (0/1)     |
|--------------------------------+------------------+------------------+----------------+-----------------|
| script/DeployUSDC.s.sol        | 0.00% (0/5)      | 0.00% (0/5)      | 100.00% (0/0)  | 0.00% (0/1)     |
|--------------------------------+------------------+------------------+----------------+-----------------|
| src/Counter.sol                | 100.00% (4/4)    | 100.00% (2/2)    | 100.00% (0/0)  | 100.00% (2/2)   |
|--------------------------------+------------------+------------------+----------------+-----------------|
| src/KipuBank.sol               | 92.68% (152/164) | 85.21% (144/169) | 48.48% (16/33) | 100.00% (34/34) |
|--------------------------------+------------------+------------------+----------------+-----------------|
| src/mocks/MockV3Aggregator.sol | 100.00% (7/7)    | 100.00% (4/4)    | 100.00% (0/0)  | 100.00% (3/3)   |
|--------------------------------+------------------+------------------+----------------+-----------------|
| src/tokens/KipuGLD.sol         | 75.00% (6/8)     | 60.00% (3/5)     | 100.00% (0/0)  | 60.00% (3/5)    |
|--------------------------------+------------------+------------------+----------------+-----------------|
| src/tokens/MockUSDC.sol        | 100.00% (2/2)    | 100.00% (2/2)    | 100.00% (0/0)  | 100.00% (2/2)   |
|--------------------------------+------------------+------------------+----------------+-----------------|
| test/KipuBank.DepositAny.t.sol | 30.43% (21/69)   | 31.48% (17/54)   | 42.86% (3/7)   | 22.22% (8/36)   |
|--------------------------------+------------------+------------------+----------------+-----------------|
| test/KipuBank.Native.t.sol     | 36.49% (27/74)   | 39.34% (24/61)   | 50.00% (5/10)  | 22.86% (8/35)   |
|--------------------------------+------------------+------------------+----------------+-----------------|
| Total                          | 53.28% (219/411) | 48.40% (196/405) | 42.86% (24/56) | 48.00% (60/125) |
╰--------------------------------+------------------+------------------+----------------+-----------------╯