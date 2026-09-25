# KABADIWALA CONNECT - Backend API
# version 0.6+


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
def calculate_distance_km(lat1, lon1, lat2, lon2):
    """
        Calculates the real-world distance (in km) between two lat/lon points
        using the Haversine formula. A simple straight-line (Pythagoras) distance
        doesn't work well on a sphere like Earth, so we use this instead.
    """
    R = 6371  # Average radius of Earth in km

    # Convert all the degrees to radians, since math.sin/cos expect radians
    lat1_rad, lon1_rad = math.radians(lat1), math.radians(lon1)
    lat2_rad, lon2_rad = math.radians(lat2), math.radians(lon2)

    dlat = lat2_rad - lat1_rad
    dlon = lon1_rad - lon2_rad

    # The Haversine formula itself
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c   # distance in kilometers


# Home Route(Home Page)
@app.get('/')
def home():
    """A simple welcome message to know if FastAPI is running."""
    return {'Message' : 'Welcome to KabaadPe'}


#1. USER REGISTRATION
@app.post("/register")
def register_user(user: UserRegister):
    """
    Register a new user (this can be a household OR a kabadiwala/collector)
    using just their name and mobile number.
    """
    if user.mobile_number in users_db:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this mobile number is already registered\n" \
            "If this is your mobile number; Please Login")

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
    Step 1 of login: request an OTP for a registered mobile number.
    In a real app this would send an SMS. Here we generate a random
    4-digit OTP using Python's `random` module and store it against
    the mobile number. We also return it in the response so you can
    test/demo the login flow without needing a real SMS gateway.
    """
    if data.mobile_number not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mobile number not registered\n" \
            "Please register first")

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
    Step 2 of login: verify the OTP the user entered, using their
    mobile number to look up the correct OTP and the user's details.
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

    # OTP is correct -> "log the user in" (no JWT/session for now, just confirm)
    user = users_db[data.mobile_number]
    return {"message": "Login successful", "user": user}


# 3. PICKUP REQUESTS
@app.post("/pickups")
def create_pickup(pickup: PickupCreate):
    """
    Create a new pickup request. A household uses this to say
    "I have scrap to give away, please come pick it up," along with
    their exact latitude/longitude so nearby collectors can find them.
    """
    if pickup.mobile_number not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='User not registered\n' \
            'Please register first')

    new_pickup = {
        # uuid4() generates a random unique ID; we keep only the first 8
        # characters since a full UUID is overkill for a prototype
        "pickup_id": str(uuid.uuid4())[:8],
        "requested_by": pickup.user_name,
        "mobile_number": pickup.mobile_number,
        "address": pickup.address,
        "latitude": pickup.latitude,
        "longitude": pickup.longitude,
        "scrap_type": pickup.scrap_type,
        "status": "pending",
        "created_at": str(datetime.now())
    }

    pickup_requests.append(new_pickup)

    return {"message": "Pickup request created successfully!", "pickup": new_pickup}


@app.get("/pickups/active")
def view_active_pickups():
    """
    View all currently active (pending) pickup requests.
    Collectors (kabadiwalas) can call this to see what pickups
    are available nearby.
    """
    active = [p for p in pickup_requests if p["status"] == "pending"]

    return {"total_pending": len(active),
            "active_pickups": active}


@app.get("/pickups/nearby")
def view_nearby_pickups(latitude: float, longitude: float, radius_km: float = 5):
    """
    Same as /pickups/active, but only returns pickups within `radius_km`
    of the collector's current location (defaults to 5 km). Each result
    gets a `distance_km` field added, and the closest pickup is listed first.
    """
    nearby = []

    for p in pickup_requests:
        if p["status"] != "pending":
            continue

        distance = calculate_distance_km(latitude, longitude, p["latitude"], p["longitude"])

        if distance <= radius_km:
            pickup_with_distance = p.copy()          # copy so we don't modify the original dict
            pickup_with_distance["distance_km"] = round(distance, 2)
            nearby.append(pickup_with_distance)

    nearby.sort(key=lambda p: p["distance_km"])   # closest pickups show up first

    return {"total_nearby": len(nearby), "nearby_pickups": nearby}


@app.post("/pickups/complete/{pickup_id}")
def update_pickup_status(pickup_id: int, data: PickupUpdate):
    """
    Called when a collector finishes weighing and paying for a pickup.
    Saves the actual weight and amount paid, then moves the pickup
    from the "active" list into "history".
    """
    for p in pickup_requests:
        if p["pickup_id"] == pickup_id and p["status"] == "pending":
            p["status"] = "completed"
            p["collector_name"] = data.collector_name
            p["sender_name"] = data.sender_name
            p["accurate_weight"] = data.accurate_weight
            p["total_amount_paid"] = data.total_amount_paid
            p["completed_at"] = str(datetime.now())

            pickup_history.append(p)
            pickup_requests.remove(p)

            return {"message": "Pickup marked as completed", "pickup": p}

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="No active pickup found with this ID")


# 4. PICKUP HISTORY
@app.get("/pickups/history/{mobile_number}")
def view_pickup_history(
    mobile_number: Optional[str] = Query(None),
    collector_name: Optional[str] = Query(None),
    sender_name: Optional[str] = Query(None)
):
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

    return {"pickup_history": results}
