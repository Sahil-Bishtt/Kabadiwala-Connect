# KABADIWALA CONNECT - Backend API
# version 0.7


from fastapi import FastAPI, HTTPException, status, Query
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, Literal

import math
import random
import uuid


app = FastAPI(title = 'Kabadiwala Connect',
              description = 'Bringing the Informal Collector into a Formal Recycling Chain')


# In Memory Databases(for now, until i develop actual databases -- lol)
users_db = {}           # key: mobile_number -> value: {"name", "mobile_number"}
otp_db = {}             # key: mobile_number -> value: current OTP(now randomly generated)
pickup_requests = []    # list of pickup dicts that are still "pending"
pickup_history = []     # list of pickup dicts that are "completed"


#Pydantic Schemas(for validation)
class UserRegister(BaseModel):
    name : str
    mobile_number : str
    user_type : Literal['Household', 'Collector']

class OTPRequest(BaseModel):
    mobile_number: str

class OTPVerify(BaseModel):
    mobile_number: str
    otp: str

class PickupCreate(BaseModel):
    user_name: str
    mobile_number: str
    address: str
    latitude: float     # needs this to calculate distance
    longitude: float
    scrap_type: list[Literal['Organic', 'Plastic', 'Paper', 'Metal', 'E-Waste', 'Other']]

class PickupUpdate(BaseModel):
    mobile_number: str
    accurate_weight: float
    total_amount_paid: float
    collector_name: str
    sender_name: str


# Helper Funtion(for proximity calculation)
def calculate_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
        Calculates the real-world distance (in km) between two lat/lon points
        using the Haversine formula.
    """
    R = 6371  # Average radius of Earth in km

    # Convert all the degrees to radians, since math.sin/cos expect radians
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    # The Haversine formula itself
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat1)) * math.sin(dlon / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c   # distance in kilometers


# Home Route(Home Page)
@app.get('/')
def home():
    """A simple welcome message to verify that the API server is active."""
    return {'Message' : 'Welcome to KabaadPe'}


# 1. USER REGISTRATION
@app.post("/register")
def register_user(user: UserRegister):
    """
    Register a new user (this can be a household OR a kabadiwala/collector)
    using just their name and mobile number.
    """
    if user.mobile_number in users_db:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this mobile number is already registered\nIf this is your mobile number; Please Login")

    users_db[user.mobile_number] = {
        "name": user.name,
        "mobile_number": user.mobile_number,
        "user_type": user.user_type}

    return {
        "message": "User registered successfully",
        "user": users_db[user.mobile_number]}


# 2. LOGIN / OTP VERIFICATION
@app.post("/login/request-otp")
def request_otp(data: OTPRequest):
    """
    Generates a dynamic 4-digit numeric OTP and stores it for verification.
    The OTP is returned in the response for prototype testing.
    """
    if data.mobile_number not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mobile number not registered\nPlease register first")

    # random.randint(0, 9999) gives a number from 0-9999,
    # and :04d pads it with leading zeros so it's always 4 digits (e.g. "0042")
    generated_otp = f"{random.randint(0, 9999):04d}"
    otp_db[data.mobile_number] = generated_otp

    return {
        "message": f"OTP sent to {data.mobile_number}",
        "otp": generated_otp}   # NOTE: only returned here for demo/testing!


@app.post("/login/verify-otp")
def verify_otp(data: OTPVerify):
    """
    Verifies the user's input OTP against the generated record.
    """
    correct_otp = otp_db.get(data.mobile_number)

    if correct_otp is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Please request an OTP first")

    if data.otp != correct_otp:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid OTP, please try again")

    #Clear the OTP after succesful verfication
    del otp_db[data.mobile_number]

    # OTP is correct -> "log the user in"
    user = users_db[data.mobile_number]
    return {"message": "Login successful", "user": user}


# 3. PICKUP REQUESTS
@app.post("/pickups")
def create_pickup(pickup: PickupCreate):
    """
    Creates a new pickup request with coordinates and a unique pickup ID.
    """
    if pickup.mobile_number not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='User not registered\nPlease register first')

    new_pickup = {
        # uuid4() generates a random unique ID; we keep only the first 8
        # characters since a full UUID is pretty overkill.
        "pickup_id": str(uuid.uuid4())[:8],
        "requested_by": pickup.user_name,
        "mobile_number": pickup.mobile_number,
        "address": pickup.address,
        "latitude": pickup.latitude,
        "longitude": pickup.longitude,
        "scrap_type": pickup.scrap_type,
        "status": "pending",
        "created_at": str(datetime.now())}

    pickup_requests.append(new_pickup)

    return {"message": "Pickup request created successfully!", "pickup": new_pickup}


@app.get("/pickups/active")
def view_active_pickups():
    """
    Returns all pending(active) pickup requests.
    """
    active = [p for p in pickup_requests if p["status"] == "pending"]

    return {"total_pending": len(active),
            "active_pickups": active}


@app.get("/pickups/nearby")
def view_nearby_pickups(latitude: float, longitude: float, radius_km: float = Query(5.0, description="Search radius in kilometers")):
    """
    Same as /pickups/active, but only returns pickups within `radius_km`
    of the collector's current location (defaults to 5 km). Each result
    gets a `distance_km` field added, and the closest pickup is listed first.
    """
    nearby = []

    for p in pickup_requests:
        if p["status"] == "pending":
            distance = calculate_distance_km(latitude, longitude, p["latitude"], p["longitude"])
            if distance <= radius_km:
                pickup_with_distance = p.copy()          # copy so we don't modify the original dict
                pickup_with_distance["distance_km"] = round(distance, 2)
                nearby.append(pickup_with_distance)

    nearby.sort(key=lambda p: p["distance_km"])   # closest pickups show up first

    return {"total_nearby": len(nearby), "nearby_pickups": nearby}


@app.post("/pickups/complete/{pickup_id}")
def update_pickup_status(pickup_id: str, data: PickupUpdate):
    """
    Marks a pickup as completed, saves actual collection weight & payout metrics, 
    and transfers the pickup into history.
    """
    for p in pickup_requests:
        if p["pickup_id"] == pickup_id and p["status"] == "pending":
            p["status"] = "completed"
            p["collector_name"] = data.collector_name
            p["sender_name"] = data.sender_name
            p["accurate_weight"] = data.accurate_weight
            p["total_amount_paid"] = data.total_amount_paid
            p["completed_at"] = str(datetime.now())

            # Transfer record to pickup_history
            pickup_history.append(p)
            pickup_requests.remove(p)

            return {"message": "Pickup marked as completed", "pickup": p}

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="No active pickup found with this ID")


# 4. PICKUP HISTORY
@app.get("/pickups/history")
def view_pickup_history(
    mobile_number: Optional[str] = Query(None, description="Filter by household mobile number"),
    collector_name: Optional[str] = Query(None, description="Filter by collector name"),
    sender_name: Optional[str] = Query(None, description="Filter by sender name")):
    """
    View past (completed) pickups.
    - Pass ?mobile_number=... to see history for a specific household.
    - Pass ?collector_name=... to see history for a specific collector.
    - Pass ?sender_name=... to see history related to a specific sender.
    - Pass none of these to see the full history.
    """

    results = pickup_history

    if mobile_number:
        results = [p for p in results if p["mobile_number"] == mobile_number]

    if collector_name:
        results = [p for p in results if p.get("collector_name") == collector_name]

    if sender_name:
        results = [p for p in results if p.get("sender_name") == sender_name]

    return {"total_records": len(results), "pickup_history": results}


# 5. Scrap Pricing
@app.get("/scrap-rates")
def get_scrap_rates():
    """
    Returns the standard market price (Rs/kg) for each scrap type.
    Households can use this to estimate what their scrap is worth,
    and collectors can use it as a reference while weighing items.
    """
    # Standard daily market rates (Rs per kg). In a real app this would come
    # from a live market feed, but a fixed dict is enough for a prototype.
    SCRAP_RATES = {
        "Plastic": 15,
        "Paper": 12,
        "Metal": 35,
        "E-Waste": 50,
        "Organic": 5
    }

    return {"scrap_rates_per_kg": SCRAP_RATES}


# 6. ANALYTICS / IMPACT DASHBOARD
@app.get("/analytics/summary")
def analytics_summary():
    """
    Calculates impact metrics across all completed pickups for SIH presentations.
    Calculates total weight collected (in KG) and total financial payment distributed to households
    """
    total_weight_kg = sum(p.get("accurate_weight", 0) for p in pickup_history)
    total_payout = sum(p.get("total_amount_paid", 0) for p in pickup_history)

    return {
        "total_completed_pickups": len(pickup_history),
        "total_recyclables_collected_kg": round(total_weight_kg, 2),
        "total_amount_paid_out": round(total_payout, 2)
    }
