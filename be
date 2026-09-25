# KABADIWALA CONNECT - Backend API
# version 0.5

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, Literal

app = FastAPI(title = 'Kabadiwala Connect',
              description = 'Bringing the Informal Collector into a Formal Recycling Chain')

#uvicorn be:app --reload
#http://127.0.0.1:8000/docs

# In Memory Databases(for now, until i develop actual databases -- lol)
users_db = {}           # key: mobile_number -> value: {"name", "mobile_number"}
otp_db = {}             # key: mobile_number -> value: current OTP(fixed for now i am lazy)
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
    scrap_type: list[Literal['Organic', 'Plastic', 'Paper', 'E-Waste', 'Metal', 'Other']]

class PickupUpdate(BaseModel):
    mobile_number: str
    accurate_weight: float
    total_amount_paid: float
    collector_name: str
    sender_name: str
    

#Home Route(Home Page)
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
    In a real app this would send an SMS. Here we just "mock" it by
    always using the OTP 1234, and storing it against the mobile number.
    """
    if data.mobile_number not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mobile number not registered\n" \
            "Please register first")

    # Mocked OTP
    otp_db[data.mobile_number] = "1234"

    return {"message": f"OTP sent to {data.mobile_number}"}     # OTP is 1234 for testing

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
    "I have scrap to give away, please come pick it up."
    """
    global next_pickup_id

    if pickup.mobile_number not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='User not registered\n' \
            'Please register first')

    new_pickup = {
        "pickup_id": len(pickup_history) + len(pickup_requests),
        "requested_by": pickup.user_name,
        "mobile_number": pickup.mobile_number,
        "address": pickup.address,
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

@app.post("/pickups/complete/{pickup_id}")
def update_pickup_status(pickup_id: int, data: PickupUpdate):
    """
    Called when a collector finishes/cancels a pickup.
    This moves the pickup from the "active" list into "history".
    """
    for p in pickup_requests:
        if p["pickup_id"] == pickup_id and p["status"] == "pending":
            p["status"] = "completed"
            p["collector_name"] = data.collector_name
            p["sender_name"] = data.sender_name
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
    mobile_number: Optional[str] = None,
    collector_name: Optional[str] = None,
    sender_name: Optional[str] = None
):
    """
    View past (completed/cancelled) pickups.
    - Pass ?mobile_number=... to see history for a specific household.
    - Pass ?collector_name=... to see history for a specific collector.
    - Pass ?sender_name=... to see history related to a specific sender.
    - Pass neither to see the full history.
    """

    results = pickup_history

    if mobile_number:
        results = [p for p in results if p["mobile_number"] == mobile_number]

    if collector_name:
        results = [p for p in results if p.get("collector_name") == collector_name]

    if sender_name:
        results = [p for p in results if p.get("sender_name") == sender_name]

    return {"pickup_history": results}
