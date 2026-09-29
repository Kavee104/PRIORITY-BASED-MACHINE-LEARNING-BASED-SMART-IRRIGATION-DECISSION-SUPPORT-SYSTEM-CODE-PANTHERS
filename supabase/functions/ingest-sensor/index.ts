import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

const DEVICE_SECRET =
  Deno.env.get("DEVICE_ESP32_ZONE_01_SECRET");

if (
  !SUPABASE_URL ||
  !SUPABASE_SERVICE_ROLE_KEY ||
  !DEVICE_SECRET
) {
  throw new Error(
    "Required environment variables are missing."
  );
}

const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  }
);

Deno.serve(async (req) => {

  // -----------------------------------------
  // ONLY ALLOW POST
  // -----------------------------------------

  if (req.method !== "POST") {
    return Response.json(
      {
        status: "error",
        message: "Method not allowed",
      },
      {
        status: 405,
      }
    );
  }


  try {

    // -----------------------------------------
    // READ JSON
    // -----------------------------------------

    const body: unknown = await req.json();

    if (
      typeof body !== "object" ||
      body === null ||
      Array.isArray(body)
    ) {
      return Response.json(
        {
          status: "error",
          message: "Invalid or missing sensor data",
        },
        {
          status: 400,
        }
      );
    }

    const payload = body as Record<string, unknown>;

    const deviceId =
      typeof payload.deviceId === "string"
        ? payload.deviceId.trim()
        : "";

    const deviceToken =
      typeof payload.deviceToken === "string"
        ? payload.deviceToken.trim()
        : "";

    const moisture = payload.moisture;

    const temperature = payload.temperature;


    // -----------------------------------------
    // VALIDATE REQUIRED VALUES
    // -----------------------------------------

    if (
      !deviceId ||
      !deviceToken ||
      typeof moisture !== "number" ||
      !Number.isFinite(moisture) ||
      typeof temperature !== "number" ||
      !Number.isFinite(temperature)
    ) {
      return Response.json(
        {
          status: "error",
          message: "Invalid or missing sensor data",
        },
        {
          status: 400,
        }
      );
    }


    // -----------------------------------------
    // BASIC RANGE CHECK
    // -----------------------------------------

    if (
      moisture < 0 ||
      moisture > 100
    ) {
      return Response.json(
        {
          status: "error",
          message: "Invalid moisture value",
        },
        {
          status: 400,
        }
      );
    }


    // -----------------------------------------
    // AUTHENTICATE ESP32
    // -----------------------------------------

    if (
      deviceId !== "ESP32_ZONE_01" ||
      deviceToken !== DEVICE_SECRET
    ) {
      return Response.json(
        {
          status: "error",
          message: "Unauthorized device",
        },
        {
          status: 401,
        }
      );
    }


    // -----------------------------------------
    // CHECK REGISTERED DEVICE
    // -----------------------------------------

    const {
      data: device,
      error: deviceError,
    } = await supabase
      .from("iot_devices")
      .select(
        "device_id, farmer_id, zone_no, active"
      )
      .eq(
        "device_id",
        deviceId
      )
      .maybeSingle();


    if (deviceError) {
      console.error(
        "Device lookup error:",
        deviceError
      );

      return Response.json(
        {
          status: "error",
          message: "Device lookup failed",
        },
        {
          status: 500,
        }
      );
    }


    if (!device) {
      return Response.json(
        {
          status: "error",
          message: "Device not registered",
        },
        {
          status: 404,
        }
      );
    }


    if (!device.active) {
      return Response.json(
        {
          status: "error",
          message: "Device disabled",
        },
        {
          status: 403,
        }
      );
    }


    // -----------------------------------------
    // STORE SENSOR READING
    // -----------------------------------------

    const {
      data: reading,
      error: readingError,
    } = await supabase
      .from("sensor_readings")
      .insert({
        device_id: deviceId,
        moisture: moisture,
        temperature: temperature,
      })
      .select("device_id, moisture, temperature, recorded_at")
      .single();


    if (readingError || !reading) {

      console.error(
        "Sensor insert error:",
        readingError
      );

      return Response.json(
        {
          status: "error",
          message: "Could not save reading",
        },
        {
          status: 500,
        }
      );
    }


    // -----------------------------------------
    // UPDATE LAST SEEN
    // -----------------------------------------

    const {
      data: updatedDevice,
      error: updateError,
    } = await supabase
      .from("iot_devices")
      .update({
        last_seen:
          new Date().toISOString(),
      })
      .eq(
        "device_id",
        deviceId
      )
      .select("device_id, last_seen")
      .single();


    if (updateError || !updatedDevice) {
      console.error(
        "Last seen update error:",
        updateError
      );

      return Response.json(
        {
          status: "error",
          message: "Could not update device status",
        },
        {
          status: 500,
        }
      );
    }


    // -----------------------------------------
    // SUCCESS
    // -----------------------------------------

    return Response.json(
      {
        status: "success",
        deviceId: deviceId,
        moisture: reading.moisture,
        temperature: reading.temperature,
        recordedAt: reading.recorded_at,
        farmerId: device.farmer_id,
        zoneNo: device.zone_no,
        lastSeen: updatedDevice.last_seen,
      },
      {
        status: 201,
      }
    );


  } catch (error) {

    console.error(error);

    return Response.json(
      {
        status: "error",
        message: "Internal server error",
      },
      {
        status: 500,
      }
    );
  }
});
