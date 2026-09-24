#version 0.5
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title = 'Kabadiwala Connect', description = 'Bringing the Informal Collector into a Formal Recycling Chain')

# In Memory Databases(for now, until i develop actual databases -- lol)
users_db = {}           # key: mobile_number -> value: {"name", "mobile_number"}

#Pydantic Schemas(for validation)
class UserRegister(BaseModel):
    name : str
    mobile_number : str
    user_type : str     # options: 'Household' or 'Collector'

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
