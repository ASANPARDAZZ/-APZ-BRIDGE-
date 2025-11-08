import client from 'prom-client';

export class BridgeMetrics {
    private bridgeTransactions: client.Counter;
    private bridgeVolume: client.Gauge;
    private bridgeErrors: client.Counter;
    private bridgeLatency: client.Histogram;

    constructor() {
        this.bridgeTransactions = new client.Counter({
            name: 'bridge_transactions_total',
            help: 'Total number of bridge transactions',
            labelNames: ['source_chain', 'destination_chain', 'status']
        });

        this.bridgeVolume = new client.Gauge({
            name: 'bridge_volume_total',
            help: 'Total volume bridged in APZ tokens',
            labelNames: ['source_chain', 'destination_chain']
        });

        this.bridgeErrors = new client.Counter({
            name: 'bridge_errors_total',
            help: 'Total number of bridge errors',
            labelNames: ['error_type', 'chain']
        });

        this.bridgeLatency = new client.Histogram({
            name: 'bridge_latency_seconds',
            help: 'Bridge transaction latency in seconds',
            labelNames: ['source_chain', 'destination_chain'],
            buckets: [30, 60, 120, 300, 600, 1800]
        });
    }

    recordTransaction(sourceChain: string, destChain: string, amount: number, status: string): void {
        this.bridgeTransactions.inc({ source_chain: sourceChain, destination_chain: destChain, status });
        if (status === 'completed') {
            this.bridgeVolume.set({ source_chain: sourceChain, destination_chain: destChain }, amount);
        }
    }

    recordError(errorType: string, chain: string): void {
        this.bridgeErrors.inc({ error_type: errorType, chain });
    }

    recordLatency(sourceChain: string, destChain: string, latency: number): void {
        this.bridgeLatency.observe({ source_chain: sourceChain, destination_chain: destChain }, latency);
    }
}
