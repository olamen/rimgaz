from django.contrib import admin

from .models import (
	Client,
	Wallet,
	Payment,
	PaymentStatusHistory,
	GasBottleType,
	ClientBottleBalance,
	Bus,
	Driver,
	Tour,
	TourStop,
	BusPosition,
	Warehouse,
	WarehouseBottleStock,
	BusBottleStock,
	GeofenceZone,
	BusAlert,
	ActivityLog,
	ClientOrder,
)


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
	list_display = ("name", "phone", "client_type", "status", "user", "created_at")
	search_fields = ("name", "phone")
	list_filter = ("client_type", "status")


@admin.register(Wallet)
class WalletAdmin(admin.ModelAdmin):
	list_display = ("client", "balance_mru", "updated_at")
	search_fields = ("client__name", "client__phone")


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
	list_display = ("client", "amount_mru", "status", "created_at")
	list_filter = ("status",)
	search_fields = ("client__name", "client__phone")
	inlines = []


@admin.register(PaymentStatusHistory)
class PaymentStatusHistoryAdmin(admin.ModelAdmin):
	list_display = ("payment", "previous_status", "new_status", "changed_by", "created_at")
	list_filter = ("new_status",)
	search_fields = ("payment__client__name", "payment__client__phone")


@admin.register(GasBottleType)
class GasBottleTypeAdmin(admin.ModelAdmin):
	list_display = ("name", "capacity_kg", "price_mru", "deposit_mru")


@admin.register(ClientBottleBalance)
class ClientBottleBalanceAdmin(admin.ModelAdmin):
	list_display = ("client", "bottle_type", "quantity")
	search_fields = ("client__name", "client__phone")


@admin.register(Bus)
class BusAdmin(admin.ModelAdmin):
	list_display = ("name", "plate_number", "capacity", "max_speed_kmh")


@admin.register(Driver)
class DriverAdmin(admin.ModelAdmin):
	list_display = ("name", "phone", "bus", "user")
	search_fields = ("name", "phone")


@admin.register(Tour)
class TourAdmin(admin.ModelAdmin):
	list_display = ("date", "sector", "bus", "driver")
	list_filter = ("date", "sector")


@admin.register(TourStop)
class TourStopAdmin(admin.ModelAdmin):
	list_display = ("tour", "client", "order_index", "status")
	list_filter = ("status",)
	search_fields = ("client__name", "client__phone")


@admin.register(BusPosition)
class BusPositionAdmin(admin.ModelAdmin):
	list_display = ("bus", "tour", "latitude", "longitude", "status", "created_at")
	list_filter = ("status", "bus")


@admin.register(Warehouse)
class WarehouseAdmin(admin.ModelAdmin):
	list_display = ("name", "address", "gps_latitude", "gps_longitude", "created_at")
	search_fields = ("name", "address")


@admin.register(WarehouseBottleStock)
class WarehouseBottleStockAdmin(admin.ModelAdmin):
	list_display = ("warehouse", "bottle_type", "quantity", "updated_at")
	list_filter = ("warehouse", "bottle_type")
	search_fields = ("warehouse__name", "bottle_type__name")


@admin.register(BusBottleStock)
class BusBottleStockAdmin(admin.ModelAdmin):
	list_display = ("bus", "bottle_type", "quantity", "updated_at")
	list_filter = ("bus", "bottle_type")
	search_fields = ("bus__name", "bottle_type__name")


@admin.register(GeofenceZone)
class GeofenceZoneAdmin(admin.ModelAdmin):
	list_display = ("name", "center_latitude", "center_longitude", "radius_meters", "is_active")
	list_filter = ("is_active",)
	search_fields = ("name",)


@admin.register(BusAlert)
class BusAlertAdmin(admin.ModelAdmin):
	list_display = ("bus", "alert_type", "message", "is_resolved", "created_at")
	list_filter = ("alert_type", "is_resolved", "bus")
	search_fields = ("bus__name", "message")


@admin.register(ActivityLog)
class ActivityLogAdmin(admin.ModelAdmin):
	list_display = ("created_at", "user", "model_name", "object_id", "action")
	list_filter = ("action", "model_name")
	search_fields = ("model_name", "object_id", "description", "user__username")


@admin.register(ClientOrder)
class ClientOrderAdmin(admin.ModelAdmin):
	list_display = ("id", "client", "bottle_type", "quantity", "total_price_mru", "status", "created_at")
	list_filter = ("status", "bottle_type")
	search_fields = ("client__name", "client__phone")
