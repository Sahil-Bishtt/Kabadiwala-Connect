#version 0.5
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional

app = FastAPI(title = 'Kabadiwala Connect', description = 'Bringing the Informal Collector into a Formal Recycling Chain')

# In Memory Databases(for now, until i develop actual databases -- lol)
users_db = {}           # key: mobile_number -> value: {"name", "mobile_number"}
otp_db = {}             # key: mobile_number -> value: current OTP(fixed for now i am lazy)

#Home Route(Home Page)
@app.get('/')
def home():
    return {'Message' : 'Welcome to KabaadPe'}

#Pydantic Schemas(for validation)
class UserRegister(BaseModel):
    name : str
    mobile_number : str
    user_type : str     # options: 'Household' or 'Collector'

class OTPRequest(BaseModel):
    mobile_number: str

class OTPVerify(BaseModel):
    mobile_number: str
    otp: str

#1. USER REGISTRATION
@app.post("/register")
def register_user(user: UserRegister):
    """
    Register a new user (this can be a household OR a kabadiwala/collector)
    using just their name and mobile number.
    """
    if user.mobile_number in users_db:
        raise HTTPException(
            status_code=400,
            detail="A user with this mobile number is already registered"
        )

    users_db[user.mobile_number] = {
        "name": user.name,
        "mobile_number": user.mobile_number
    }

    return {
        "message": "User registered successfully",
        "user": users_db[user.mobile_number]
    }

# 2. LOGIN / OTP VERIFICATION
@app.post("/login/request-otp")
def request_otp(data: OTPRequest):
    """
    Step 1 of login: request an OTP for a registered mobile number.
    In a real app this would send an SMS. Here we just "mock" it by
    always using the OTP 1234, and storing it against the mobile number.
    """
    if data.mobile_number not in users_db:
        raise HTTPException(status_code=404, detail="Mobile number not registered")

    # Mocked OTP - in real life you would generate a random code and send an SMS
    otp_db[data.mobile_number] = "1234"

    return {"message": f"OTP sent to {data.mobile_number} (hint: it's 1234 for testing)"}

@app.post("/login/verify-otp")
def verify_otp(data: OTPVerify):
    """
    Step 2 of login: verify the OTP the user entered, using their
    mobile number to look up the correct OTP and the user's details.
    """
    correct_otp = otp_db.get(data.mobile_number)

    if correct_otp is None:
        raise HTTPException(status_code=400, detail="Please request an OTP first")

    if data.otp != correct_otp:
        raise HTTPException(status_code=400, detail="Invalid OTP, please try again")

    # OTP is correct -> "log the user in" (no JWT/session for now, just confirm)
    user = users_db[data.mobile_number]
    return {"message": "Login successful", "user": user}

