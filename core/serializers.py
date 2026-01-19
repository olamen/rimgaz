from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.contrib.auth.models import Permission

from .models import (
    Client,
    Bus,
    Driver,
    Tour,
    TourStop,
    BusPosition,
    Wallet,
    Payment,
    PaymentStatusHistory,
    GasBottleType,
    ClientBottleBalance,
    Warehouse,
    WarehouseBottleStock,
    BusBottleStock,
    GeofenceZone,
    BusAlert,
    ActivityLog,
    ClientOrder,
    
)


User = get_user_model()


class ClientSerializer(serializers.ModelSerializer):
    has_pending_delivery = serializers.SerializerMethodField()

    class Meta:
        model = Client
        fields = [
            "id",
            "name",
            "phone",
            "whatsapp",
            "address",
            "gps_latitude",
            "gps_longitude",
            "client_type",
            "language",
            "status",
            "has_pending_delivery",
            "created_at",
            "updated_at",
        ]

    def get_has_pending_delivery(self, obj):
        return obj.tour_stops.filter(status=TourStop.PENDING).exists()


class WalletSerializer(serializers.ModelSerializer):
    client = ClientSerializer(read_only=True)

    class Meta:
        model = Wallet
        fields = ["id", "client", "balance_mru", "created_at", "updated_at"]


class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = [
            "id",
            "client",
            "amount_mru",
            "method",
            "receipt_image",
            "status",
            "rejection_reason",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]


class ClientSelfPaymentSerializer(serializers.ModelSerializer):
    order_id = serializers.IntegerField(source="order.id", read_only=True)
    order_status = serializers.CharField(source="order.status", read_only=True)

    class Meta:
        model = Payment
        fields = [
            "id",
            "order_id",
            "order_status",
            "amount_mru",
            "method",
            "receipt_image",
            "status",
            "created_at",
        ]
        read_only_fields = ["status", "created_at"]


class PaymentStatusHistorySerializer(serializers.ModelSerializer):
    payment_id = serializers.IntegerField(source="payment.id", read_only=True)
    client_name = serializers.CharField(source="payment.client.name", read_only=True)
    client_phone = serializers.CharField(source="payment.client.phone", read_only=True)
    amount_mru = serializers.DecimalField(source="payment.amount_mru", max_digits=14, decimal_places=2, read_only=True)
    changed_by_username = serializers.CharField(source="changed_by.username", read_only=True, default=None)

    class Meta:
        model = PaymentStatusHistory
        fields = [
            "id",
            "payment_id",
            "client_name",
            "client_phone",
            "amount_mru",
            "previous_status",
            "new_status",
            "changed_by_username",
            "note",
            "created_at",
        ]


class GasBottleTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = GasBottleType
        fields = [
            "id",
            "name",
            "capacity_kg",
            "price_mru",
            "deposit_mru",
            "created_at",
            "updated_at",
        ]


class ClientOrderSerializer(serializers.ModelSerializer):
    client = serializers.CharField(source="client.name", read_only=True)
    client_id = serializers.IntegerField(source="client.id", read_only=True)
    client_address = serializers.CharField(source="client.address", read_only=True)
    client_gps_latitude = serializers.DecimalField(
        max_digits=9,
        decimal_places=6,
        source="client.gps_latitude",
        read_only=True,
        allow_null=True,
    )
    client_gps_longitude = serializers.DecimalField(
        max_digits=9,
        decimal_places=6,
        source="client.gps_longitude",
        read_only=True,
        allow_null=True,
    )
    bottle_type = GasBottleTypeSerializer(read_only=True)
    bottle_type_id = serializers.PrimaryKeyRelatedField(
        queryset=GasBottleType.objects.all(), source="bottle_type", write_only=True
    )
    delivered_by_name = serializers.CharField(source="delivered_by.name", read_only=True, default=None)

    class Meta:
        model = ClientOrder
        fields = [
            "id",
            "client",
            "client_id",
            "client_address",
            "client_gps_latitude",
            "client_gps_longitude",
            "bottle_type",
            "bottle_type_id",
            "quantity",
            "unit_price_mru",
            "total_price_mru",
            "status",
            "delivered_at",
            "delivered_by_name",
            "created_at",
        ]
        # status et les champs de livraison sont gérés côté back-office / API dédiée
        read_only_fields = [
            "unit_price_mru",
            "total_price_mru",
            "created_at",
            "delivered_at",
            "delivered_by_name",
        ]


class UserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=False, allow_blank=True)
    # Indique si l'utilisateur a le droit de valider les paiements (rôle financier)
    can_validate_payments = serializers.SerializerMethodField(read_only=True)
    # Champ d'aide pour (dé)finir le rôle financier lors de la création/mise à jour
    is_financial = serializers.BooleanField(write_only=True, required=False)

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "password",
            "email",
            "is_active",
            "is_staff",
            "is_superuser",
            "can_validate_payments",
            "is_financial",
        ]
        read_only_fields = ["id", "can_validate_payments"]

    def get_can_validate_payments(self, obj):
        try:
            return obj.has_perm("core.can_validate_payments")
        except Exception:
            return False

    def _set_financial_permission(self, user, is_financial: bool):
        """Ajoute ou retire le droit core.can_validate_payments à l'utilisateur."""
        try:
            perm = Permission.objects.get(codename="can_validate_payments", content_type__app_label="core")
        except Permission.DoesNotExist:
            return
        if is_financial:
            user.user_permissions.add(perm)
        else:
            user.user_permissions.remove(perm)

    def create(self, validated_data):
        password = validated_data.pop("password", None)
        is_financial = validated_data.pop("is_financial", False)
        user = User(**validated_data)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save()
        if is_financial:
            self._set_financial_permission(user, True)
        return user

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        is_financial = validated_data.pop("is_financial", None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        if password:
            instance.set_password(password)
        instance.save()
        if is_financial is not None:
            self._set_financial_permission(instance, bool(is_financial))
        return instance


class ClientBottleBalanceSerializer(serializers.ModelSerializer):
    client = ClientSerializer(read_only=True)
    bottle_type = GasBottleTypeSerializer(read_only=True)

    class Meta:
        model = ClientBottleBalance
        fields = [
            "id",
            "client",
            "bottle_type",
            "quantity",
            "created_at",
            "updated_at",
        ]


class BusSerializer(serializers.ModelSerializer):
    class Meta:
        model = Bus
        fields = [
            "id",
            "name",
            "plate_number",
            "capacity",
            "max_speed_kmh",
            "created_at",
            "updated_at",
        ]


class DriverSerializer(serializers.ModelSerializer):
    bus = serializers.PrimaryKeyRelatedField(
        queryset=Bus.objects.all(), allow_null=True, required=False
    )

    class Meta:
        model = Driver
        fields = ["id", "name", "phone", "bus", "created_at", "updated_at"]


class TourSerializer(serializers.ModelSerializer):
    bus = serializers.PrimaryKeyRelatedField(queryset=Bus.objects.all())
    driver = serializers.PrimaryKeyRelatedField(
        queryset=Driver.objects.all(), allow_null=True, required=False
    )

    class Meta:
        model = Tour
        fields = [
            "id",
            "date",
            "sector",
            "bus",
            "driver",
            "created_at",
            "updated_at",
        ]


class TourStopSerializer(serializers.ModelSerializer):
    class Meta:
        model = TourStop
        fields = [
            "id",
            "tour",
            "client",
            "order_index",
            "status",
            "delivered_bottles",
            "returned_bottles",
            "created_at",
            "updated_at",
        ]


class BusPositionSerializer(serializers.ModelSerializer):
    has_alert = serializers.SerializerMethodField()

    class Meta:
        model = BusPosition
        fields = [
            "id",
            "bus",
            "tour",
            "latitude",
            "longitude",
            "status",
            "speed_kmh",
            "has_alert",
            "created_at",
            "updated_at",
        ]

    def get_has_alert(self, obj):
        return obj.alerts.filter(is_resolved=False).exists()


class GeofenceZoneSerializer(serializers.ModelSerializer):
    class Meta:
        model = GeofenceZone
        fields = [
            "id",
            "name",
            "center_latitude",
            "center_longitude",
            "radius_meters",
            "polygon",
            "is_active",
            "created_at",
            "updated_at",
        ]


class BusAlertSerializer(serializers.ModelSerializer):
    bus = BusSerializer(read_only=True)
    position = BusPositionSerializer(read_only=True)

    class Meta:
        model = BusAlert
        fields = [
            "id",
            "bus",
            "position",
            "alert_type",
            "message",
            "is_resolved",
            "created_at",
            "updated_at",
        ]


class WarehouseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Warehouse
        fields = [
            "id",
            "name",
            "address",
            "gps_latitude",
            "gps_longitude",
            "created_at",
            "updated_at",
        ]


class WarehouseBottleStockSerializer(serializers.ModelSerializer):
    warehouse = WarehouseSerializer(read_only=True)
    bottle_type = GasBottleTypeSerializer(read_only=True)
    warehouse_id = serializers.PrimaryKeyRelatedField(
        queryset=Warehouse.objects.all(), source="warehouse", write_only=True
    )
    bottle_type_id = serializers.PrimaryKeyRelatedField(
        queryset=GasBottleType.objects.all(), source="bottle_type", write_only=True
    )

    class Meta:
        model = WarehouseBottleStock
        fields = [
            "id",
            "warehouse",
            "bottle_type",
            "warehouse_id",
            "bottle_type_id",
            "quantity",
            "created_at",
            "updated_at",
        ]


class ActivityLogSerializer(serializers.ModelSerializer):
    user_username = serializers.CharField(source="user.username", read_only=True, default=None)

    class Meta:
        model = ActivityLog
        fields = [
            "id",
            "created_at",
            "user_username",
            "model_name",
            "object_id",
            "action",
            "description",
            "data",
        ]


class BusBottleStockSerializer(serializers.ModelSerializer):
    bus = BusSerializer(read_only=True)
    bottle_type = GasBottleTypeSerializer(read_only=True)
    bus_id = serializers.PrimaryKeyRelatedField(
        queryset=Bus.objects.all(), source="bus", write_only=True
    )
    bottle_type_id = serializers.PrimaryKeyRelatedField(
        queryset=GasBottleType.objects.all(), source="bottle_type", write_only=True
    )

    class Meta:
        model = BusBottleStock
        fields = [
            "id",
            "bus",
            "bottle_type",
            "bus_id",
            "bottle_type_id",
            "quantity",
            "created_at",
            "updated_at",
        ]
