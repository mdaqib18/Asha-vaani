from fastapi import FastAPI

from app.api.routes import router
from app.core.errors import register_error_handlers

app = FastAPI(title="Asha Vaani")
register_error_handlers(app)
app.include_router(router)
