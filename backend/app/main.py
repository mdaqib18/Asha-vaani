from fastapi import FastAPI

from app.api.routes import router

app = FastAPI(title="Asha Vaani")
app.include_router(router)
