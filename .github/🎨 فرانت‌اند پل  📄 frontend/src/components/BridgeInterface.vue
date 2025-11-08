<template>
    <div class="bridge-interface">
        <div class="card">
            <h2>🌉 APZ Cross-Chain Bridge</h2>
            
            <div class="network-selector">
                <div class="from-network">
                    <label>From Network</label>
                    <select v-model="fromNetwork" @change="updateNetworks">
                        <option value="ethereum">Ethereum</option>
                        <option value="apz">APZ Chain</option>
                        <option value="bsc">BSC</option>
                        <option value="polygon">Polygon</option>
                    </select>
                </div>
                
                <div class="swap-button">
                    <button @click="swapNetworks">⇄</button>
                </div>
                
                <div class="to-network">
                    <label>To Network</label>
                    <select v-model="toNetwork" @change="updateNetworks">
                        <option value="ethereum">Ethereum</option>
                        <option value="apz">APZ Chain</option>
                        <option value="bsc">BSC</option>
                        <option value="polygon">Polygon</option>
                    </select>
                </div>
            </div>

            <div class="amount-input">
                <label>Amount to Bridge</label>
                <div class="input-group">
                    <input 
                        v-model="amount" 
                        type="number" 
                        :placeholder="`Min: ${minAmount} ${tokenSymbol}`"
                        :min="minAmount"
                        :max="maxAmount"
                    />
                    <button @click="setMaxAmount">MAX</button>
                </div>
                <div class="balance">
                    Balance: {{ formatBalance(balance) }} {{ tokenSymbol }}
                </div>
            </div>

            <div class="fee-display">
                <div class="fee-item">
                    <span>Bridge Fee:</span>
                    <span>{{ bridgeFee }}%</span>
                </div>
                <div class="fee-item">
                    <span>You will receive:</span>
                    <span>{{ receiveAmount }} {{ tokenSymbol }}</span>
                </div>
                <div class="fee-item">
                    <span>Estimated Time:</span>
                    <span>{{ estimatedTime }}</span>
                </div>
            </div>

            <button 
                class="bridge-button" 
                :disabled="!canBridge"
                @click="initiateBridge"
            >
                {{ bridgeButtonText }}
            </button>

            <div v-if="transactionHash" class="transaction-info">
                <h4>Transaction Submitted</h4>
                <a :href="explorerUrl" target="_blank">
                    View on Explorer: {{ shortHash(transactionHash) }}
                </a>
            </div>
        </div>

        <!-- Transaction History -->
        <div class="transaction-history">
            <h3>Recent Transactions</h3>
            <div v-for="tx in transactions" :key="tx.hash" class="transaction-item">
                <div class="tx-info">
                    <div class="tx-amount">{{ tx.amount }} {{ tokenSymbol }}</div>
                    <div class="tx-networks">{{ tx.from }} → {{ tx.to }}</div>
                    <div class="tx-status" :class="tx.status">{{ tx.status }}</div>
                </div>
                <div class="tx-time">{{ formatTime(tx.timestamp) }}</div>
            </div>
        </div>
    </div>
</template>

<script>
import { ethers } from 'ethers';
import { ref, computed, onMounted } from 'vue';

export default {
    name: 'BridgeInterface',
    setup() {
        const fromNetwork = ref('ethereum');
        const toNetwork = ref('apz');
        const amount = ref('');
        const balance = ref(0);
        const transactionHash = ref('');
        const transactions = ref([]);

        const tokenSymbol = 'APZ';
        const minAmount = 1;
        const maxAmount = 100000;
        const bridgeFee = 0.1;

        const receiveAmount = computed(() => {
            if (!amount.value) return 0;
            const amt = parseFloat(amount.value);
            return (amt * (1 - bridgeFee / 100)).toFixed(4);
        });

        const canBridge = computed(() => {
            const amt = parseFloat(amount.value);
            return amt >= minAmount && amt <= maxAmount && amt <= balance.value;
        });

        const bridgeButtonText = computed(() => {
            if (!amount.value) return 'Enter Amount';
            if (parseFloat(amount.value) < minAmount) return 'Amount Too Low';
            if (parseFloat(amount.value) > balance.value) return 'Insufficient Balance';
            return 'Bridge Tokens';
        });

        const estimatedTime = computed(() => {
            return '5-15 minutes';
        });

        const explorerUrl = computed(() => {
            const baseUrls = {
                ethereum: 'https://etherscan.io/tx/',
                apz: 'https://explorer.apzchain.org/tx/',
                bsc: 'https://bscscan.com/tx/',
                polygon: 'https://polygonscan.com/tx/'
            };
            return `${baseUrls[fromNetwork.value]}${transactionHash.value}`;
        });

        function updateNetworks() {
            if (fromNetwork.value === toNetwork.value) {
                // Find a different network
                const networks = ['ethereum', 'apz', 'bsc', 'polygon'];
                toNetwork.value = networks.find(net => net !== fromNetwork.value) || 'apz';
            }
        }

        function swapNetworks() {
            [fromNetwork.value, toNetwork.value] = [toNetwork.value, fromNetwork.value];
        }

        function setMaxAmount() {
            amount.value = balance.value.toString();
        }

        function formatBalance(bal) {
            return parseFloat(bal).toFixed(4);
        }

        function shortHash(hash) {
            return `${hash.substring(0, 6)}...${hash.substring(hash.length - 4)}`;
        }

        function formatTime(timestamp) {
            return new Date(timestamp).toLocaleString();
        }

        async function initiateBridge() {
            try {
                // Connect to wallet
                if (!window.ethereum) {
                    alert('Please install MetaMask!');
                    return;
                }

                await window.ethereum.request({ method: 'eth_requestAccounts' });
                const provider = new ethers.providers.Web3Provider(window.ethereum);
                const signer = provider.getSigner();
                
                // Get bridge contract
                const bridgeContract = new ethers.Contract(
                    getBridgeAddress(fromNetwork.value),
                    getBridgeABI(),
                    signer
                );

                // Execute bridge transaction
                const tx = await bridgeContract.lockTokens(
                    ethers.utils.parseEther(amount.value),
                    toNetwork.value,
                    await signer.getAddress()
                );

                transactionHash.value = tx.hash;
                
                // Add to transaction history
                transactions.value.unshift({
                    hash: tx.hash,
                    amount: amount.value,
                    from: fromNetwork.value,
                    to: toNetwork.value,
                    status: 'pending',
                    timestamp: Date.now()
                });

                // Wait for confirmation
                await tx.wait();
                
                // Update transaction status
                const txIndex = transactions.value.findIndex(t => t.hash === tx.hash);
                if (txIndex !== -1) {
                    transactions.value[txIndex].status = 'completed';
                }

            } catch (error) {
                console.error('Bridge transaction failed:', error);
                alert('Bridge transaction failed. Please try again.');
            }
        }

        function getBridgeAddress(network) {
            const addresses = {
                ethereum: '0x...',
                apz: '0x...',
                bsc: '0x...',
                polygon: '0x...'
            };
            return addresses[network];
        }

        function getBridgeABI() {
            // Bridge contract ABI
            return [];
        }

        async function loadBalance() {
            if (window.ethereum) {
                const provider = new ethers.providers.Web3Provider(window.ethereum);
                const signer = provider.getSigner();
                const address = await signer.getAddress();
                
                // Load token balance
                const tokenContract = new ethers.Contract(
                    getTokenAddress(fromNetwork.value),
                    ['function balanceOf(address) view returns (uint256)'],
                    provider
                );
                
                const bal = await tokenContract.balanceOf(address);
                balance.value = parseFloat(ethers.utils.formatEther(bal));
            }
        }

        onMounted(() => {
            loadBalance();
        });

        return {
            fromNetwork,
            toNetwork,
            amount,
            balance,
            transactionHash,
            transactions,
            tokenSymbol,
            minAmount,
            maxAmount,
            bridgeFee,
            receiveAmount,
            estimatedTime,
            canBridge,
            bridgeButtonText,
            explorerUrl,
            updateNetworks,
            swapNetworks,
            setMaxAmount,
            formatBalance,
            shortHash,
            formatTime,
            initiateBridge
        };
    }
};
</script>

<style scoped>
.bridge-interface {
    max-width: 500px;
    margin: 0 auto;
    padding: 20px;
}

.card {
    background: white;
    border-radius: 12px;
    padding: 24px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
    margin-bottom: 20px;
}

.network-selector {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 20px;
}

.from-network, .to-network {
    flex: 1;
}

.swap-button button {
    background: #f0f0f0;
    border: none;
    border-radius: 8px;
    padding: 8px 12px;
    cursor: pointer;
}

.amount-input {
    margin-bottom: 20px;
}

.input-group {
    display: flex;
    gap: 8px;
}

.input-group input {
    flex: 1;
    padding: 12px;
    border: 1px solid #ddd;
    border-radius: 8px;
}

.input-group button {
    background: #f0f0f0;
    border: 1px solid #ddd;
    border-radius: 8px;
    padding: 12px 16px;
    cursor: pointer;
}

.balance {
    font-size: 12px;
    color: #666;
    margin-top: 4px;
}

.fee-display {
    background: #f8f9fa;
    padding: 16px;
    border-radius: 8px;
    margin-bottom: 20px;
}

.fee-item {
    display: flex;
    justify-content: space-between;
    margin-bottom: 8px;
}

.fee-item:last-child {
    margin-bottom: 0;
}

.bridge-button {
    width: 100%;
    background: #007bff;
    color: white;
    border: none;
    border-radius: 8px;
    padding: 16px;
    font-size: 16px;
    cursor: pointer;
}

.bridge-button:disabled {
    background: #ccc;
    cursor: not-allowed;
}

.transaction-info {
    margin-top: 16px;
    padding: 12px;
    background: #e7f3ff;
    border-radius: 8px;
    text-align: center;
}

.transaction-history {
    background: white;
    border-radius: 12px;
    padding: 24px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.transaction-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 0;
    border-bottom: 1px solid #eee;
}

.transaction-item:last-child {
    border-bottom: none;
}

.tx-status.completed {
    color: #28a745;
}

.tx-status.pending {
    color: #ffc107;
}

.tx-status.failed {
    color: #dc3545;
}
</style>
