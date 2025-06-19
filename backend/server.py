from fastapi import FastAPI, APIRouter, HTTPException
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
from pathlib import Path
from pydantic import BaseModel, Field
from typing import List, Optional
import uuid
from datetime import datetime, timedelta
import random


ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ['DB_NAME']]

# Create the main app without a prefix
app = FastAPI(title="EigenLVR API", description="API for EigenLVR Loss Versus Rebalancing mitigation system")

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")


# Define Models
class StatusCheck(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    client_name: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class StatusCheckCreate(BaseModel):
    client_name: str

class AuctionSummary(BaseModel):
    activeAuctions: int
    totalMEVRecovered: str
    totalLPRewards: str
    avsOperatorCount: int

class AuctionRecord(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    poolId: str
    winner: str
    winningBid: str
    totalBids: int
    timestamp: str
    status: str = "completed"
    blockNumber: int

class PoolPerformance(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    poolId: str
    tvl: str
    lvrReduction: float
    rewardsDistributed: str
    lastUpdated: datetime = Field(default_factory=datetime.utcnow)

class AVSOperator(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    address: str
    stake: str
    status: str = "active"
    tasksCompleted: int
    reputation: float
    lastSeen: datetime = Field(default_factory=datetime.utcnow)

# Basic routes
@api_router.get("/")
async def root():
    return {"message": "EigenLVR API - Loss Versus Rebalancing Mitigation System"}

@api_router.post("/status", response_model=StatusCheck)
async def create_status_check(input: StatusCheckCreate):
    status_dict = input.dict()
    status_obj = StatusCheck(**status_dict)
    _ = await db.status_checks.insert_one(status_obj.dict())
    return status_obj

@api_router.get("/status", response_model=List[StatusCheck])
async def get_status_checks():
    status_checks = await db.status_checks.find().to_list(1000)
    return [StatusCheck(**status_check) for status_check in status_checks]

# EigenLVR specific routes
@api_router.get("/auctions/summary", response_model=AuctionSummary)
async def get_auction_summary():
    """Get summary statistics for auctions and MEV recovery"""
    # In production, this would query actual data from the database
    # For demo purposes, we'll return mock data with some variation
    
    base_time = datetime.now()
    active_auctions = random.randint(0, 5)
    total_mev = round(random.uniform(50.0, 200.0), 2)
    total_rewards = round(total_mev * 0.85, 2)  # 85% goes to LPs
    operator_count = random.randint(8, 15)
    
    return AuctionSummary(
        activeAuctions=active_auctions,
        totalMEVRecovered=str(total_mev),
        totalLPRewards=str(total_rewards),
        avsOperatorCount=operator_count
    )

@api_router.get("/auctions/recent", response_model=List[AuctionRecord])
async def get_recent_auctions():
    """Get recent auction records"""
    # Mock data for demonstration
    auctions = []
    
    for i in range(10):
        pool_id = f"0x{random.randint(100000000, 999999999):x}{'0' * 23}"
        winner = f"0x{random.randint(100000000, 999999999):x}{'0' * 23}"
        winning_bid = round(random.uniform(0.1, 5.0), 3)
        total_bids = random.randint(3, 12)
        timestamp = (datetime.now() - timedelta(minutes=random.randint(5, 1440))).strftime("%Y-%m-%d %H:%M:%S")
        block_number = random.randint(18500000, 18600000)
        
        auction = AuctionRecord(
            poolId=pool_id,
            winner=winner,
            winningBid=str(winning_bid),
            totalBids=total_bids,
            timestamp=timestamp,
            blockNumber=block_number
        )
        auctions.append(auction)
    
    return sorted(auctions, key=lambda x: x.timestamp, reverse=True)

@api_router.get("/pools/performance", response_model=List[PoolPerformance])
async def get_pool_performance():
    """Get pool performance metrics"""
    pools = []
    
    pool_names = ["ETH/USDC", "ETH/USDT", "WBTC/ETH", "DAI/USDC", "LINK/ETH"]
    
    for i, name in enumerate(pool_names):
        pool_id = f"0x{random.randint(100000000, 999999999):x}{'0' * 23}"
        tvl = f"{random.randint(1000000, 50000000):,}"
        lvr_reduction = round(random.uniform(0.5, 8.5), 1)
        rewards = round(random.uniform(5.0, 25.0), 2)
        
        pool = PoolPerformance(
            name=name,
            poolId=pool_id,
            tvl=tvl,
            lvrReduction=lvr_reduction,
            rewardsDistributed=str(rewards)
        )
        pools.append(pool)
    
    return pools

@api_router.get("/operators", response_model=List[AVSOperator])
async def get_avs_operators():
    """Get AVS operator information"""
    operators = []
    
    for i in range(12):
        address = f"0x{random.randint(100000000, 999999999):x}{'0' * 23}"
        stake = f"{random.randint(1000, 10000)}"
        status = random.choice(["active", "active", "active", "inactive"])  # Weighted towards active
        tasks_completed = random.randint(50, 500)
        reputation = round(random.uniform(0.7, 1.0), 2)
        
        operator = AVSOperator(
            address=address,
            stake=stake,
            status=status,
            tasksCompleted=tasks_completed,
            reputation=reputation
        )
        operators.append(operator)
    
    return operators

@api_router.get("/auctions/{auction_id}")
async def get_auction_details(auction_id: str):
    """Get detailed information about a specific auction"""
    # Mock detailed auction data
    return {
        "id": auction_id,
        "poolId": f"0x{random.randint(100000000, 999999999):x}{'0' * 23}",
        "status": "completed",
        "startTime": (datetime.now() - timedelta(minutes=5)).isoformat(),
        "endTime": datetime.now().isoformat(),
        "winner": f"0x{random.randint(100000000, 999999999):x}{'0' * 23}",
        "winningBid": str(round(random.uniform(1.0, 5.0), 3)),
        "totalBids": random.randint(5, 15),
        "participants": [
            {
                "address": f"0x{random.randint(100000000, 999999999):x}{'0' * 23}",
                "bid": str(round(random.uniform(0.5, 4.0), 3)),
                "timestamp": (datetime.now() - timedelta(minutes=random.randint(1, 4))).isoformat()
            }
            for _ in range(random.randint(3, 8))
        ],
        "lvrAmount": str(round(random.uniform(2.0, 10.0), 3)),
        "gasUsed": random.randint(150000, 300000),
        "blockNumber": random.randint(18500000, 18600000)
    }

@api_router.post("/auctions", status_code=201)
async def create_auction(auction: AuctionRecord):
    """Create a new auction record (used by the hook contract)"""
    auction_dict = auction.dict()
    result = await db.auctions.insert_one(auction_dict)
    return {"id": str(result.inserted_id), "message": "Auction created successfully"}

@api_router.get("/pools/{pool_id}/metrics")
async def get_pool_metrics(pool_id: str):
    """Get detailed metrics for a specific pool"""
    return {
        "poolId": pool_id,
        "totalVolume24h": f"{random.randint(1000000, 10000000):,}",
        "fees24h": f"{random.randint(1000, 10000):,}",
        "lvrDetected": random.randint(5, 25),
        "auctionsTriggered": random.randint(3, 20),
        "mevRecovered": str(round(random.uniform(10.0, 100.0), 2)),
        "lpRewardsDistributed": str(round(random.uniform(8.0, 85.0), 2)),
        "avgAuctionParticipation": random.randint(3, 12),
        "priceImpactReduction": f"{round(random.uniform(0.1, 2.5), 2)}%"
    }

@api_router.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0",
        "services": {
            "database": "connected",
            "avs": "operational",
            "price_oracle": "active"
        }
    }

# Include the router in the main app
app.include_router(api_router)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()
