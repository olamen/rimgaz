import os
import sys

# Assure-toi que le chemin du projet est dans sys.path
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
if PROJECT_ROOT not in sys.path:
    sys.path.append(PROJECT_ROOT)

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'rimgaz_backend.settings')

from django.core.wsgi import get_wsgi_application
application = get_wsgi_application()