// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IUBI4ALLQuantum.sol";

/// @title UBI4ALLQuantum - Token Q4A per trading con leva avanzata
/// @notice Gestisce il token Q4A con allocazioni, lock per DAO, vesting e supporto per trading con leva
contract UBI4ALLQuantum is ERC20, Ownable, ReentrancyGuard, Pausable, IUBI4ALLQuantum {
    using SafeMath for uint256;

    /// @dev Total supply del token Q4A (1 miliardo di token, 18 decimali)
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    /// @dev Allocazione per il treasury (50%)
    uint256 public constant TREASURY_ALLOCATION = (TOTAL_SUPPLY * 50) / 100;
    /// @dev Allocazione per l'ecosistema (20%)
    uint256 public constant ECOSYSTEM_ALLOCATION = (TOTAL_SUPPLY * 20) / 100;
    /// @dev Allocazione per la comunità (15%)
    uint256 public constant COMMUNITY_ALLOCATION = (TOTAL_SUPPLY * 15) / 100;
    /// @dev Allocazione per la liquidità (10%)
    uint256 public constant LIQUIDITY_ALLOCATION = (TOTAL_SUPPLY * 10) / 100;
    /// @dev Allocazione per la riserva (5%)
    uint256 public constant RESERVE_ALLOCATION = (TOTAL_SUPPLY * 5) / 100;

    /// @dev Periodo di vesting (1 anno)
    uint256 public constant VESTING_PERIOD = 365 days;
    /// @dev Timestamp di inizio del vesting
    uint256 public immutable vestingStart;

    /// @dev Wallet per le allocazioni
    address public treasuryWallet;
    address public ecosystemWallet;
    address public communityWallet;
    address public liquidityWallet;
    address public reserveWallet;

    /// @dev Mappatura dei token bloccati per la DAO
    mapping(address => uint256) public lockedForDAO;
    /// @dev Totale dei token bloccati per la DAO
    uint256 public totalLockedForDAO;

    /// @dev Struttura per il vesting
    struct VestingSchedule {
        uint256 totalAmount; // Importo totale in vesting
        uint256 releasedAmount; // Importo già rilasciato
    }

    /// @dev Mappatura dei vesting per wallet
    mapping(address => VestingSchedule) public vestingSchedules;

    /// @notice Evento emesso per trasferimenti di token
    event QuantumTransfer(address indexed from, address indexed to, uint256 amount);
    /// @notice Evento emesso per token bloccati per la DAO
    event TokensLockedForDAO(address indexed account, uint256 amount);
    /// @notice Evento emesso per token sbloccati dalla DAO
    event TokensUnlockedForDAO(address indexed account, uint256 amount);
    /// @notice Evento emesso per rilascio di token in vesting
    event VestingReleased(address indexed wallet, uint256 amount);
    /// @notice Evento emesso per trasferimenti con leva
    event LeveragedTransfer(address indexed from, address indexed to, uint256 amount, uint256 leverage);

    /// @notice Costruttore del contratto
    /// @param _treasuryWallet Indirizzo del wallet treasury
    /// @param _ecosystemWallet Indirizzo del wallet ecosistema
    /// @param _communityWallet Indirizzo del wallet comunità
    /// @param _liquidityWallet Indirizzo del wallet liquidità
    /// @param _reserveWallet Indirizzo del wallet riserva
    /// @param initialOwner Indirizzo del proprietario iniziale
    constructor(
        address _treasuryWallet,
        address _ecosystemWallet,
        address _communityWallet,
        address _liquidityWallet,
        address _reserveWallet,
        address initialOwner
    ) ERC20("Quantum UBI4ALL", "Q4A") Ownable(initialOwner) {
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        require(_ecosystemWallet != address(0), "Invalid ecosystem wallet");
        require(_communityWallet != address(0), "Invalid community wallet");
        require(_liquidityWallet != address(0), "Invalid liquidity wallet");
        require(_reserveWallet != address(0), "Invalid reserve wallet");

        treasuryWallet = _treasuryWallet;
        ecosystemWallet = _ecosystemWallet;
        communityWallet = _communityWallet;
        liquidityWallet = _liquidityWallet;
        reserveWallet = _reserveWallet;

        vestingStart = block.timestamp;

        // Inizializza i vesting per treasury ed ecosistema
        vestingSchedules[treasuryWallet] = VestingSchedule(TREASURY_ALLOCATION, 0);
        vestingSchedules[ecosystemWallet] = VestingSchedule(ECOSYSTEM_ALLOCATION, 0);

        // Mint iniziale con vesting
        _mint(address(this), TREASURY_ALLOCATION + ECOSYSTEM_ALLOCATION);
        _mint(communityWallet, COMMUNITY_ALLOCATION);
        _mint(liquidityWallet, LIQUIDITY_ALLOCATION);
        _mint(reserveWallet, RESERVE_ALLOCATION);
    }

    /// @notice Ottiene il total supply del token
    /// @return Total supply (1 miliardo di Q4A)
    function getTotalSupply() external pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice Ottiene le allocazioni dei token
    /// @return treasury Allocazione treasury
    /// @return ecosystem Allocazione ecosistema
    /// @return community Allocazione comunità
    /// @return liquidity Allocazione liquidità
    /// @return reserve Allocazione riserva
    function getAllocations() external pure override returns (
        uint256 treasury,
        uint256 ecosystem,
        uint256 community,
        uint256 liquidity,
        uint256 reserve
    ) {
        return (
            TREASURY_ALLOCATION,
            ECOSYSTEM_ALLOCATION,
            COMMUNITY_ALLOCATION,
            LIQUIDITY_ALLOCATION,
            RESERVE_ALLOCATION
        );
    }

    /// @notice Ottiene gli indirizzi dei wallet
    /// @return treasury Indirizzo wallet treasury
    /// @return ecosystem Indirizzo wallet ecosistema
    /// @return community Indirizzo wallet comunità
    /// @return liquidity Indirizzo wallet liquidità
    /// @return reserve Indirizzo wallet riserva
    function getWallets() external view override returns (
        address treasury,
        address ecosystem,
        address community,
        address liquidity,
        address reserve
    ) {
        return (
            treasuryWallet,
            ecosystemWallet,
            communityWallet,
            liquidityWallet,
            reserveWallet
        );
    }

    /// @notice Minta nuovi token
    /// @param to Indirizzo del destinatario
    /// @param amount Quantità di token da mintare
    function mint(address to, uint256 amount) external override onlyOwner nonReentrant whenNotPaused {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        _mint(to, amount);
    }

    /// @notice Brucia token dal chiamante
    /// @param amount Quantità di token da bruciare
    function burn(uint256 amount) external override nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    /// @notice Recupera token ERC20 bloccati nel contratto
    /// @param token Indirizzo del token da recuperare
    /// @param to Indirizzo del destinatario
    function emergencyRecoverTokens(address token, address to) external override onlyOwner nonReentrant {
        require(token != address(this), "Cannot recover Q4A tokens");
        require(to != address(0), "Invalid recipient");
        uint256 amount = IERC20(token).balanceOf(address(this));
        require(amount > 0, "No tokens to recover");
        IERC20(token).transfer(to, amount);
        emit EmergencyRecovery(token, to, amount);
    }

    /// @notice Aggiorna l'indirizzo di un wallet
    /// @param walletType Tipo di wallet ("treasury", "ecosystem", "community", "liquidity", "reserve")
    /// @param newWallet Nuovo indirizzo del wallet
    function updateWallet(string memory walletType, address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid wallet address");
        bytes32 walletHash = keccak256(abi.encodePacked(walletType));
        if (walletHash == keccak256(abi.encodePacked("treasury"))) {
            require(newWallet != treasuryWallet, "Same wallet address");
            vestingSchedules[newWallet] = vestingSchedules[treasuryWallet];
            delete vestingSchedules[treasuryWallet];
            treasuryWallet = newWallet;
        } else if (walletHash == keccak256(abi.encodePacked("ecosystem"))) {
            require(newWallet != ecosystemWallet, "Same wallet address");
            vestingSchedules[newWallet] = vestingSchedules[ecosystemWallet];
            delete vestingSchedules[ecosystemWallet];
            ecosystemWallet = newWallet;
        } else if (walletHash == keccak256(abi.encodePacked("community"))) {
            require(newWallet != communityWallet, "Same wallet address");
            communityWallet = newWallet;
        } else if (walletHash == keccak256(abi.encodePacked("liquidity"))) {
            require(newWallet != liquidityWallet, "Same wallet address");
            liquidityWallet = newWallet;
        } else if (walletHash == keccak256(abi.encodePacked("reserve"))) {
            require(newWallet != reserveWallet, "Same wallet address");
            reserveWallet = newWallet;
        } else {
            revert("Invalid wallet type");
        }
        emit WalletUpdated(walletType, newWallet);
    }

    /// @notice Blocca token per la DAO
    /// @param amount Quantità di token da bloccare
    function lockForDAO(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        lockedForDAO[msg.sender] = lockedForDAO[msg.sender].add(amount);
        totalLockedForDAO = totalLockedForDAO.add(amount);
        emit TokensLockedForDAO(msg.sender, amount);
    }

    /// @notice Sblocca token dalla DAO
    /// @param amount Quantità di token da sbloccare
    function unlockFromDAO(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(lockedForDAO[msg.sender] >= amount, "Insufficient locked balance");
        lockedForDAO[msg.sender] = lockedForDAO[msg.sender].sub(amount);
        totalLockedForDAO = totalLockedForDAO.sub(amount);
        _mint(msg.sender, amount);
        emit TokensUnlockedForDAO(msg.sender, amount);
    }

    /// @notice Rilascia i token in vesting per un wallet
    /// @param wallet Indirizzo del wallet in vesting
    function releaseVesting(address wallet) external nonReentrant whenNotPaused {
        require(wallet == treasuryWallet || wallet == ecosystemWallet, "Invalid vesting wallet");
        VestingSchedule storage schedule = vestingSchedules[wallet];
        require(schedule.totalAmount > schedule.releasedAmount, "No tokens to release");

        uint256 elapsedTime = block.timestamp.sub(vestingStart);
        uint256 vestedAmount = schedule.totalAmount.mul(elapsedTime).div(VESTING_PERIOD);
        if (vestedAmount > schedule.totalAmount) {
            vestedAmount = schedule.totalAmount;
        }

        uint256 releasable = vestedAmount.sub(schedule.releasedAmount);
        require(releasable > 0, "No tokens releasable");

        schedule.releasedAmount = schedule.releasedAmount.add(releasable);
        _transfer(address(this), wallet, releasable);
        emit VestingReleased(wallet, releasable);
    }

    /// @notice Ottiene l'importo di token in vesting rilasciabile per un wallet
    /// @param wallet Indirizzo del wallet
    /// @return Importo rilasciabile
    function getReleasableVesting(address wallet) external view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[wallet];
        if (schedule.totalAmount == 0) return 0;

        uint256 elapsedTime = block.timestamp.sub(vestingStart);
        uint256 vestedAmount = schedule.totalAmount.mul(elapsedTime).div(VESTING_PERIOD);
        if (vestedAmount > schedule.totalAmount) {
            vestedAmount = schedule.totalAmount;
        }

        return vestedAmount.sub(schedule.releasedAmount);
    }

    /// @notice Trasferisce token con supporto per leva (per trading avanzato)
    /// @param to Indirizzo del destinatario
    /// @param amount Quantità di token da trasferire
    /// @param leverage Fattore di leva (es. 100 = 1x, 200 = 2x)
    /// @return True se il trasferimento ha successo
    function transferWithLeverage(address to, uint256 amount, uint256 leverage) external nonReentrant whenNotPaused returns (bool) {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(leverage >= 100, "Leverage must be at least 1x");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Nota: La logica di leva può essere integrata con UBI4ALLTrading e UBI4ALLOracle
        // Qui simuliamo un trasferimento con leva emettendo un evento
        bool success = super.transfer(to, amount);
        if (success) {
            emit LeveragedTransfer(msg.sender, to, amount, leverage);
        }
        return success;
    }

    /// @notice Trasferisce token (con supporto per leva futura)
    /// @param to Indirizzo del destinatario
    /// @param amount Quantità di token da trasferire
    /// @return True se il trasferimento ha successo
    function transfer(address to, uint256 amount) public override(ERC20, IUBI4ALLQuantum) whenNotPaused returns (bool) {
        bool success = super.transfer(to, amount);
        if (success) {
            emit QuantumTransfer(msg.sender, to, amount);
        }
        return success;
    }

    /// @notice Ottiene il saldo di un account
    /// @param account Indirizzo dell'account
    /// @return Saldo dell'account
    function balanceOf(address account) public view override(ERC20, IUBI4ALLQuantum) returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice Mette in pausa il contratto
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Ripristina il contratto dalla pausa
    function unpause() external onlyOwner {
        _unpause();
    }
}