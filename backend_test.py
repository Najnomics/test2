#!/usr/bin/env python3
import requests
import json
import uuid
import sys
from datetime import datetime
from typing import Dict, Any, List, Optional

# Get the backend URL from the frontend .env file
BACKEND_URL = "https://03daad31-84ce-4757-bf8e-36cfeb8be1fb.preview.emergentagent.com"
API_BASE_URL = f"{BACKEND_URL}/api"

class TestResult:
    def __init__(self, endpoint: str, method: str):
        self.endpoint = endpoint
        self.method = method
        self.status_code: Optional[int] = None
        self.response_data: Optional[Dict[str, Any]] = None
        self.success: bool = False
        self.error_message: Optional[str] = None
        
    def __str__(self) -> str:
        status = "✅ PASSED" if self.success else "❌ FAILED"
        return f"{status} | {self.method} {self.endpoint} | Status: {self.status_code}"
    
    def details(self) -> str:
        if not self.success:
            return f"  Error: {self.error_message}"
        
        if isinstance(self.response_data, list) and len(self.response_data) > 0:
            return f"  Response: List with {len(self.response_data)} items"
        elif isinstance(self.response_data, dict):
            return f"  Response: {json.dumps(self.response_data, indent=2)[:200]}..."
        else:
            return f"  Response: {str(self.response_data)[:200]}"

def test_endpoint(method: str, endpoint: str, data: Optional[Dict[str, Any]] = None) -> TestResult:
    """Test an API endpoint and return the result"""
    url = f"{API_BASE_URL}{endpoint}"
    result = TestResult(endpoint, method)
    
    try:
        if method.upper() == "GET":
            response = requests.get(url)
        elif method.upper() == "POST":
            response = requests.post(url, json=data)
        else:
            result.error_message = f"Unsupported method: {method}"
            return result
        
        result.status_code = response.status_code
        
        # Check if the response is valid JSON
        try:
            result.response_data = response.json()
        except json.JSONDecodeError:
            result.error_message = "Invalid JSON response"
            return result
        
        # Check if the status code is successful (2xx)
        if 200 <= response.status_code < 300:
            result.success = True
        else:
            result.error_message = f"Unexpected status code: {response.status_code}"
            
    except requests.RequestException as e:
        result.error_message = f"Request failed: {str(e)}"
    
    return result

def run_tests() -> List[TestResult]:
    """Run all API tests and return the results"""
    results = []
    
    # Test basic endpoints
    results.append(test_endpoint("GET", "/"))
    results.append(test_endpoint("GET", "/health"))
    
    # Test EigenLVR specific endpoints
    results.append(test_endpoint("GET", "/auctions/summary"))
    results.append(test_endpoint("GET", "/auctions/recent"))
    results.append(test_endpoint("GET", "/pools/performance"))
    results.append(test_endpoint("GET", "/operators"))
    
    # Test endpoints with parameters
    # Generate a random auction ID for testing
    auction_id = str(uuid.uuid4())
    results.append(test_endpoint("GET", f"/auctions/{auction_id}"))
    
    # Generate a random pool ID for testing
    pool_id = f"0x{uuid.uuid4().hex[:40]}"
    results.append(test_endpoint("GET", f"/pools/{pool_id}/metrics"))
    
    # Test POST endpoint to create an auction
    auction_data = {
        "poolId": f"0x{uuid.uuid4().hex[:40]}",
        "winner": f"0x{uuid.uuid4().hex[:40]}",
        "winningBid": "1.234",
        "totalBids": 5,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "blockNumber": 18550000
    }
    results.append(test_endpoint("POST", "/auctions", auction_data))
    
    return results

def validate_response_schema(results: List[TestResult]) -> List[Dict[str, Any]]:
    """Validate the response schema for each endpoint"""
    schema_validation = []
    
    for result in results:
        if not result.success:
            continue
            
        validation = {
            "endpoint": result.endpoint,
            "method": result.method,
            "valid_schema": True,
            "issues": []
        }
        
        # Validate schema based on endpoint
        if result.endpoint == "/":
            if not isinstance(result.response_data, dict) or "message" not in result.response_data:
                validation["valid_schema"] = False
                validation["issues"].append("Missing 'message' field in root endpoint response")
                
        elif result.endpoint == "/health":
            required_fields = ["status", "timestamp", "version", "services"]
            for field in required_fields:
                if field not in result.response_data:
                    validation["valid_schema"] = False
                    validation["issues"].append(f"Missing '{field}' field in health check response")
        
        elif result.endpoint == "/auctions/summary":
            required_fields = ["activeAuctions", "totalMEVRecovered", "totalLPRewards", "avsOperatorCount"]
            for field in required_fields:
                if field not in result.response_data:
                    validation["valid_schema"] = False
                    validation["issues"].append(f"Missing '{field}' field in auction summary response")
        
        elif result.endpoint == "/auctions/recent":
            if not isinstance(result.response_data, list):
                validation["valid_schema"] = False
                validation["issues"].append("Response is not a list of auction records")
            elif len(result.response_data) > 0:
                required_fields = ["id", "poolId", "winner", "winningBid", "totalBids", "timestamp", "blockNumber"]
                for field in required_fields:
                    if field not in result.response_data[0]:
                        validation["valid_schema"] = False
                        validation["issues"].append(f"Missing '{field}' field in auction record")
        
        elif result.endpoint == "/pools/performance":
            if not isinstance(result.response_data, list):
                validation["valid_schema"] = False
                validation["issues"].append("Response is not a list of pool performance records")
            elif len(result.response_data) > 0:
                required_fields = ["id", "name", "poolId", "tvl", "lvrReduction", "rewardsDistributed"]
                for field in required_fields:
                    if field not in result.response_data[0]:
                        validation["valid_schema"] = False
                        validation["issues"].append(f"Missing '{field}' field in pool performance record")
        
        elif result.endpoint == "/operators":
            if not isinstance(result.response_data, list):
                validation["valid_schema"] = False
                validation["issues"].append("Response is not a list of AVS operators")
            elif len(result.response_data) > 0:
                required_fields = ["id", "address", "stake", "status", "tasksCompleted", "reputation"]
                for field in required_fields:
                    if field not in result.response_data[0]:
                        validation["valid_schema"] = False
                        validation["issues"].append(f"Missing '{field}' field in AVS operator record")
        
        elif result.endpoint.startswith("/auctions/") and not result.endpoint == "/auctions/recent" and not result.endpoint == "/auctions/summary":
            required_fields = ["id", "poolId", "status", "startTime", "endTime", "winner", "winningBid", "totalBids", "participants"]
            for field in required_fields:
                if field not in result.response_data:
                    validation["valid_schema"] = False
                    validation["issues"].append(f"Missing '{field}' field in auction details response")
        
        elif result.endpoint.startswith("/pools/") and result.endpoint.endswith("/metrics"):
            required_fields = ["poolId", "totalVolume24h", "fees24h", "lvrDetected", "auctionsTriggered", "mevRecovered", "lpRewardsDistributed"]
            for field in required_fields:
                if field not in result.response_data:
                    validation["valid_schema"] = False
                    validation["issues"].append(f"Missing '{field}' field in pool metrics response")
        
        elif result.endpoint == "/auctions" and result.method == "POST":
            required_fields = ["id", "message"]
            for field in required_fields:
                if field not in result.response_data:
                    validation["valid_schema"] = False
                    validation["issues"].append(f"Missing '{field}' field in auction creation response")
        
        schema_validation.append(validation)
    
    return schema_validation

def main():
    print(f"🧪 Testing EigenLVR Backend API at {API_BASE_URL}")
    print("=" * 80)
    
    # Run all tests
    results = run_tests()
    
    # Print test results
    for result in results:
        print(result)
        if not result.success:
            print(result.details())
    
    print("\n" + "=" * 80)
    
    # Validate response schemas
    schema_validations = validate_response_schema(results)
    
    # Print schema validation results
    print("\n🔍 Schema Validation Results:")
    for validation in schema_validations:
        status = "✅ Valid" if validation["valid_schema"] else "❌ Invalid"
        print(f"{status} | {validation['method']} {validation['endpoint']}")
        if not validation["valid_schema"]:
            for issue in validation["issues"]:
                print(f"  - {issue}")
    
    # Calculate overall test results
    total_tests = len(results)
    passed_tests = sum(1 for result in results if result.success)
    valid_schemas = sum(1 for validation in schema_validations if validation["valid_schema"])
    
    print("\n" + "=" * 80)
    print(f"📊 Test Summary: {passed_tests}/{total_tests} tests passed, {valid_schemas}/{len(schema_validations)} valid schemas")
    
    # Return exit code based on test results
    if passed_tests == total_tests and valid_schemas == len(schema_validations):
        print("✅ All tests passed successfully!")
        return 0
    else:
        print("❌ Some tests failed. See details above.")
        return 1

if __name__ == "__main__":
    sys.exit(main())