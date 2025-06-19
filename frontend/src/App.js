import React, { useState, useEffect } from "react";
import { BrowserRouter, Routes, Route, Link } from "react-router-dom";
import axios from "axios";
import "./App.css";

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL;
const API = `${BACKEND_URL}/api`;

// Main Dashboard Component
const Dashboard = () => {
  const [auctionData, setAuctionData] = useState({
    activeAuctions: 0,
    totalMEVRecovered: "0",
    totalLPRewards: "0",
    avsOperatorCount: 0
  });
  
  const [recentAuctions, setRecentAuctions] = useState([]);
  const [poolPerformance, setPoolPerformance] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchDashboardData();
    const interval = setInterval(fetchDashboardData, 10000); // Update every 10 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchDashboardData = async () => {
    try {
      const [auctionsResp, poolsResp, performanceResp] = await Promise.all([
        axios.get(`${API}/auctions/summary`),
        axios.get(`${API}/auctions/recent`),
        axios.get(`${API}/pools/performance`)
      ]);

      setAuctionData(auctionsResp.data);
      setRecentAuctions(poolsResp.data);
      setPoolPerformance(performanceResp.data);
      setLoading(false);
    } catch (error) {
      console.error("Error fetching dashboard data:", error);
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-900 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-blue-500 mx-auto"></div>
          <p className="text-white mt-4">Loading EigenLVR Dashboard...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      {/* Header */}
      <header className="bg-gray-800 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <img 
                  className="h-8 w-8" 
                  src="https://avatars.githubusercontent.com/in/1201222?s=120&u=2686cf91179bbafbc7a71bfbc43004cf9ae1acea&v=4" 
                  alt="EigenLVR"
                />
              </div>
              <div className="ml-4">
                <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
                  EigenLVR Dashboard
                </h1>
                <p className="text-gray-400 text-sm">Loss Versus Rebalancing Mitigation</p>
              </div>
            </div>
            <div className="flex items-center space-x-4">
              <div className="flex items-center space-x-2">
                <div className="w-3 h-3 bg-green-500 rounded-full animate-pulse"></div>
                <span className="text-sm text-gray-300">AVS Active</span>
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <StatCard
            title="Active Auctions"
            value={auctionData.activeAuctions}
            icon="🔨"
            color="blue"
          />
          <StatCard
            title="Total MEV Recovered"
            value={`${auctionData.totalMEVRecovered} ETH`}
            icon="💰"
            color="green"
          />
          <StatCard
            title="LP Rewards Distributed"
            value={`${auctionData.totalLPRewards} ETH`}
            icon="🎁"
            color="purple"
          />
          <StatCard
            title="AVS Operators"
            value={auctionData.avsOperatorCount}
            icon="⚡"
            color="yellow"
          />
        </div>

        {/* Recent Auctions & Pool Performance */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <RecentAuctions auctions={recentAuctions} />
          <PoolPerformance pools={poolPerformance} />
        </div>

        {/* LVR Explanation */}
        <div className="mt-8">
          <LVRExplanation />
        </div>
      </main>
    </div>
  );
};

// Stat Card Component
const StatCard = ({ title, value, icon, color }) => {
  const colorClasses = {
    blue: "border-blue-500 bg-blue-500/10",
    green: "border-green-500 bg-green-500/10",
    purple: "border-purple-500 bg-purple-500/10",
    yellow: "border-yellow-500 bg-yellow-500/10"
  };

  return (
    <div className={`bg-gray-800 rounded-lg border-2 ${colorClasses[color]} p-6`}>
      <div className="flex items-center">
        <div className="text-2xl mr-3">{icon}</div>
        <div>
          <p className="text-gray-400 text-sm">{title}</p>
          <p className="text-2xl font-bold text-white">{value}</p>
        </div>
      </div>
    </div>
  );
};

// Recent Auctions Component
const RecentAuctions = ({ auctions }) => {
  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h2 className="text-xl font-bold mb-4 flex items-center">
        <span className="mr-2">🏆</span>
        Recent Auctions
      </h2>
      <div className="space-y-4">
        {auctions.length > 0 ? (
          auctions.slice(0, 5).map((auction, index) => (
            <div key={index} className="border-l-4 border-blue-500 pl-4 py-2">
              <div className="flex justify-between items-center">
                <div>
                  <p className="font-semibold">Pool: {auction.poolId?.slice(0, 10)}...</p>
                  <p className="text-sm text-gray-400">Winner: {auction.winner?.slice(0, 10)}...</p>
                </div>
                <div className="text-right">
                  <p className="font-bold text-green-400">{auction.winningBid} ETH</p>
                  <p className="text-xs text-gray-400">{auction.timestamp}</p>
                </div>
              </div>
            </div>
          ))
        ) : (
          <div className="text-center py-8">
            <p className="text-gray-400">No recent auctions</p>
            <p className="text-sm text-gray-500 mt-2">Auctions will appear here when LVR opportunities are detected</p>
          </div>
        )}
      </div>
    </div>
  );
};

// Pool Performance Component
const PoolPerformance = ({ pools }) => {
  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h2 className="text-xl font-bold mb-4 flex items-center">
        <span className="mr-2">📊</span>
        Pool Performance
      </h2>
      <div className="space-y-4">
        {pools.length > 0 ? (
          pools.slice(0, 5).map((pool, index) => (
            <div key={index} className="flex justify-between items-center py-2 border-b border-gray-700">
              <div>
                <p className="font-semibold">{pool.name || `Pool ${index + 1}`}</p>
                <p className="text-sm text-gray-400">TVL: ${pool.tvl || "0"}</p>
              </div>
              <div className="text-right">
                <p className={`font-bold ${pool.lvrReduction >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                  {pool.lvrReduction || 0}% LVR Reduction
                </p>
                <p className="text-xs text-gray-400">{pool.rewardsDistributed || 0} ETH Rewards</p>
              </div>
            </div>
          ))
        ) : (
          <div className="text-center py-8">
            <p className="text-gray-400">No pools tracked yet</p>
            <p className="text-sm text-gray-500 mt-2">Pool performance data will appear when hooks are deployed</p>
          </div>
        )}
      </div>
    </div>
  );
};

// LVR Explanation Component
const LVRExplanation = () => {
  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h2 className="text-xl font-bold mb-4 flex items-center">
        <span className="mr-2">🧠</span>
        How EigenLVR Works
      </h2>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="text-center">
          <div className="text-4xl mb-3">⚡</div>
          <h3 className="font-bold mb-2">LVR Detection</h3>
          <p className="text-sm text-gray-400">
            Our price oracles continuously monitor off-chain vs on-chain price discrepancies, 
            detecting profitable arbitrage opportunities.
          </p>
        </div>
        <div className="text-center">
          <div className="text-4xl mb-3">🏺</div>
          <h3 className="font-bold mb-2">Sealed-Bid Auctions</h3>
          <p className="text-sm text-gray-400">
            When LVR is detected, EigenLayer AVS operators run sealed-bid auctions to 
            determine who gets first transaction priority.
          </p>
        </div>
        <div className="text-center">
          <div className="text-4xl mb-3">💎</div>
          <h3 className="font-bold mb-2">Value Return</h3>
          <p className="text-sm text-gray-400">
            Auction proceeds are automatically distributed to liquidity providers, 
            returning MEV that would otherwise be lost to arbitrageurs.
          </p>
        </div>
      </div>
    </div>
  );
};

// Navigation Component
const Navigation = () => {
  return (
    <nav className="bg-gray-800 shadow-lg">
      <div className="max-w-7xl mx-auto px-4">
        <div className="flex justify-between h-16">
          <div className="flex items-center space-x-8">
            <Link to="/" className="text-white hover:text-blue-400 transition-colors">
              Dashboard
            </Link>
            <Link to="/auctions" className="text-gray-300 hover:text-blue-400 transition-colors">
              Auctions
            </Link>
            <Link to="/pools" className="text-gray-300 hover:text-blue-400 transition-colors">
              Pools
            </Link>
            <Link to="/operators" className="text-gray-300 hover:text-blue-400 transition-colors">
              AVS Operators
            </Link>
          </div>
        </div>
      </div>
    </nav>
  );
};

// Placeholder Components for Routes
const AuctionsPage = () => (
  <div className="min-h-screen bg-gray-900 text-white p-8">
    <h1 className="text-3xl font-bold mb-6">Auction History</h1>
    <p className="text-gray-400">Detailed auction history and analytics coming soon...</p>
  </div>
);

const PoolsPage = () => (
  <div className="min-h-screen bg-gray-900 text-white p-8">
    <h1 className="text-3xl font-bold mb-6">Pool Management</h1>
    <p className="text-gray-400">Pool management and configuration coming soon...</p>
  </div>
);

const OperatorsPage = () => (
  <div className="min-h-screen bg-gray-900 text-white p-8">
    <h1 className="text-3xl font-bold mb-6">AVS Operators</h1>
    <p className="text-gray-400">AVS operator status and management coming soon...</p>
  </div>
);

// Main App Component
function App() {
  return (
    <div className="App">
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/auctions" element={<AuctionsPage />} />
          <Route path="/pools" element={<PoolsPage />} />
          <Route path="/operators" element={<OperatorsPage />} />
        </Routes>
      </BrowserRouter>
    </div>
  );
}

export default App;