#!/bin/bash

# EigenLVR Startup Script
echo "🔗 Starting EigenLVR System..."

# Create necessary directories
mkdir -p ./avs/keys
mkdir -p ./deployments
mkdir -p ./logs

# Generate placeholder key files if they don't exist
if [ ! -f "./avs/keys/operator.ecdsa.key.json" ]; then
    echo "Creating placeholder operator ECDSA key..."
    echo '{"address":"0x0000000000000000000000000000000000000000","privateKey":"0x0000000000000000000000000000000000000000000000000000000000000000"}' > ./avs/keys/operator.ecdsa.key.json
fi

if [ ! -f "./avs/keys/operator.bls.key.json" ]; then
    echo "Creating placeholder operator BLS key..."
    echo '{"privateKey":"0x0000000000000000000000000000000000000000000000000000000000000000"}' > ./avs/keys/operator.bls.key.json
fi

if [ ! -f "./avs/keys/aggregator.ecdsa.key.json" ]; then
    echo "Creating placeholder aggregator ECDSA key..."
    echo '{"address":"0x0000000000000000000000000000000000000000","privateKey":"0x0000000000000000000000000000000000000000000000000000000000000000"}' > ./avs/keys/aggregator.ecdsa.key.json
fi

echo "✅ Key files created (placeholder keys for demo)"

# Start the applications
echo "🚀 Starting backend and frontend services..."

# The supervisor will handle starting backend and frontend
# This script is for any additional setup needed

echo "📊 EigenLVR System is ready!"
echo ""
echo "🌐 Frontend Dashboard: Available via supervisor"
echo "🔌 Backend API: Available via supervisor"  
echo "⚡ AVS Operator: Run 'cd avs && go run cmd/operator/main.go'"
echo "🔄 AVS Aggregator: Run 'cd avs && go run cmd/aggregator/main.go'"
echo ""
echo "📚 Next steps:"
echo "1. Configure actual RPC URLs in avs/config/*.yaml"
echo "2. Generate real cryptographic keys for production"
echo "3. Deploy smart contracts to testnet/mainnet"
echo "4. Register AVS operators with EigenLayer"
echo ""
echo "💡 This is a development demo. Do not use in production without proper key management and security audits."