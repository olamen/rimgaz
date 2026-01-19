from django.apps import AppConfig


class CoreConfig(AppConfig):
    name = 'core'
    default_auto_field = 'django.db.models.BigAutoField'

    def ready(self) -> None:
        from . import signals  # noqa: F401
        return super().ready()
