"""
URL configuration for rimgaz_backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
from django.contrib.auth import views as auth_views
from django.conf import settings
from django.conf.urls.static import static
from rest_framework_simplejwt.views import TokenRefreshView

from rest_framework import routers

from core.views import (
    ClientViewSet,
    UserViewSet,
    BusViewSet,
    DriverViewSet,
    TourViewSet,
    BusPositionViewSet,
    WalletViewSet,
    PaymentViewSet,
    PaymentStatusHistoryViewSet,
    GasBottleTypeViewSet,
    ClientBottleBalanceViewSet,
    GeofenceZoneViewSet,
    BusAlertViewSet,
    ActivityLogViewSet,
    WarehouseViewSet,
    WarehouseBottleStockViewSet,
    BusBottleStockViewSet,
    admin_dashboard,
    dashboard_clients,
    dashboard_buses,
    dashboard_drivers,
    dashboard_tours,
    dashboard_payments,
    dashboard_wallets,
    dashboard_payment_history,
    dashboard_client_orders,
    dashboard_bottle_types,
    dashboard_bottle_balances,
    dashboard_activity_log,
    dashboard_bus_positions,
    dashboard_warehouses,
    dashboard_warehouse_stocks,
    dashboard_bus_stocks,
    dashboard_bus_alerts,
    dashboard_geofences,
    dashboard_users,
    logout_view,
    ClientPaymentViewSet,
    ClientOrderViewSet,
    DriverOrderViewSet,
)
        
from core.auth_api import RimgazTokenObtainPairView

router = routers.DefaultRouter()
router.register(r"users", UserViewSet, basename="users")
router.register(r"clients", ClientViewSet)
router.register(r"buses", BusViewSet)
router.register(r"drivers", DriverViewSet)
router.register(r"tours", TourViewSet)
router.register(r"bus-positions", BusPositionViewSet, basename="bus-positions")
router.register(r"wallets", WalletViewSet, basename="wallets")
router.register(r"payments", PaymentViewSet, basename="payments")
router.register(r"payment-status-history", PaymentStatusHistoryViewSet, basename="payment-status-history")
router.register(r"bottle-types", GasBottleTypeViewSet, basename="bottle-types")
router.register(r"client-bottle-balances", ClientBottleBalanceViewSet, basename="client-bottle-balances")
router.register(r"geofences", GeofenceZoneViewSet, basename="geofences")
router.register(r"bus-alerts", BusAlertViewSet, basename="bus-alerts")
router.register(r"warehouses", WarehouseViewSet, basename="warehouses")
router.register(r"warehouse-stocks", WarehouseBottleStockViewSet, basename="warehouse-stocks")
router.register(r"bus-stocks", BusBottleStockViewSet, basename="bus-stocks")
router.register(r"activity-logs", ActivityLogViewSet, basename="activity-logs")
router.register(r"client-payments", ClientPaymentViewSet, basename="client-payments")
router.register(r"driver-orders", DriverOrderViewSet, basename="driver-orders")
router.register(r"client-orders", ClientOrderViewSet, basename="client-orders")


urlpatterns = [
    path("admin/", admin.site.urls),
    path("login/", auth_views.LoginView.as_view(template_name="core/login.html"), name="login"),
    path("logout/", logout_view, name="logout"),
    path("dashboard/", admin_dashboard, name="admin-dashboard"),
    path("dashboard/clients/", dashboard_clients, name="dashboard-clients"),
    path("dashboard/buses/", dashboard_buses, name="dashboard-buses"),
    path("dashboard/drivers/", dashboard_drivers, name="dashboard-drivers"),
    path("dashboard/tours/", dashboard_tours, name="dashboard-tours"),
    path("dashboard/payments/", dashboard_payments, name="dashboard-payments"),
    path("dashboard/wallets/", dashboard_wallets, name="dashboard-wallets"),
    path("dashboard/payment-history/", dashboard_payment_history, name="dashboard-payment-history"),
    path("dashboard/client-orders/", dashboard_client_orders, name="dashboard-client-orders"),
    path("dashboard/bottle-types/", dashboard_bottle_types, name="dashboard-bottle-types"),
    path("dashboard/bottle-balances/", dashboard_bottle_balances, name="dashboard-bottle-balances"),
    path("dashboard/activity-log/", dashboard_activity_log, name="dashboard-activity-log"),
    path("dashboard/bus-positions/", dashboard_bus_positions, name="dashboard-bus-positions"),
    path("dashboard/warehouses/", dashboard_warehouses, name="dashboard-warehouses"),
    path("dashboard/warehouse-stocks/", dashboard_warehouse_stocks, name="dashboard-warehouse-stocks"),
    path("dashboard/bus-stocks/", dashboard_bus_stocks, name="dashboard-bus-stocks"),
    path("dashboard/bus-alerts/", dashboard_bus_alerts, name="dashboard-bus-alerts"),
    path("dashboard/geofences/", dashboard_geofences, name="dashboard-geofences"),
    path("dashboard/users/", dashboard_users, name="dashboard-users"),
    path("api/token/", RimgazTokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("api/token/refresh/", TokenRefreshView.as_view(), name="token_refresh"),
    path("api/", include(router.urls)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
