module sand.saned;

import sand.sane;
import std.exception : enforce, assertThrown;
import std.algorithm.iteration, std.string;
import std.conv, std.range, std.variant;

// A somewhat sane interface to sane
class Sane {
    int versionMajor, versionMinor, versionBuild;
    Device[] m_devices;

    this() {
    }

    ~this() {
        sane_exit();
    }

    void init() {
        int api_version;
        auto status = sane_init(&api_version, null);
        enforce(status == SANE_Status.SANE_STATUS_GOOD);
        SANE_VERSION_CODE(versionMajor, versionMinor, versionBuild);
    }

    auto devices(bool force=false) {
    	if(!m_devices.length || force) {
           SANE_Device** device_list;
           auto status = sane_get_devices(&device_list, true);
           auto size = 0;
           while(*(device_list + size))
               size++;
            m_devices =  device_list[0 .. size].map!(device => new Device(device)).array;
	}
	return m_devices;
    }
}

class Device {
    string name;
    string vendor;
    string model;
    string type;
    SANE_Device* device;
    private Option[] m_options;
    private SANE_Handle handle;
    private bool open;

    this(SANE_Device* device) {
        name = to!string((*device).name);
        vendor = to!string((*device).vendor);
        model = to!string((*device).model);
        type = to!string((*device).type);
        this.device = device;
        sane_open(device.name, &handle);
    }

    override string toString() {
        return format("SANE Device: %s - %s", vendor, model);
    }

    @property auto options() {
        if(!open) {
            populateOptions();
            open = true;
        }
        return m_options;
    }

    private void populateOptions() {
        auto size = 0;
        while(sane_get_option_descriptor(handle, size))
            size++;
        m_options = iota(size).map!(i => new Option(handle, i)).array;
    }

    auto readImage() {
        sane_start(handle);
        SANE_Parameters params;
        enforce(sane_get_parameters(handle, &params) == SANE_Status.SANE_STATUS_GOOD);
        auto totalBytes = params.lines * params.bytes_per_line;
        ubyte[] data = new ubyte[totalBytes];
        int length, offset;
        SANE_Status status;
        do {
            status = sane_read(handle, data.ptr, totalBytes, &length);
            offset += length;
        } while (status == SANE_Status.SANE_STATUS_GOOD);
        return data;
    }
}

class Option {
    int number;
    const string name;
    const string title;
    const string description;
    const string unit;
    private SANE_Handle handle;

    this(SANE_Handle handle, int number) {
        this.number = number;
        auto descriptor = sane_get_option_descriptor(handle, number);
        name = to!string((*descriptor).name);
        title = to!string((*descriptor).title);
        description = to!string((*descriptor).desc);
        unit = unitToString(descriptor.unit);
        this.handle = handle;
    }

    override string toString() {
        return format("Option:\nName: %s\nTitle: %s\nDescription: %s\nUnit: %s" ~
                      "\nSettable: %s\nActive: %s", name, title, description, unit, settable(), active());
    }

    private string unitToString(SANE_Unit unit) {
        switch(unit) {
        case SANE_Unit.SANE_UNIT_NONE:
            return "(none)";
        case SANE_Unit.SANE_UNIT_PIXEL:
            return "pixels";
        case SANE_Unit.SANE_UNIT_BIT:
            return "bits";
        case SANE_Unit.SANE_UNIT_MM:
            return "millimetres";
        case SANE_Unit.SANE_UNIT_DPI:
            return "dots per inch";
        case SANE_Unit.SANE_UNIT_PERCENT:
            return "percentage";
        case SANE_Unit.SANE_UNIT_MICROSECOND:
            return "microseconds";
        default:
            assert(0);
        }
    }

    @property bool settable() {
        return SANE_OPTION_IS_SETTABLE(sane_get_option_descriptor(handle, number).cap);
    }

    @property bool active() {
        return SANE_OPTION_IS_ACTIVE(sane_get_option_descriptor(handle, number).cap);
    }

    @property auto value() {
        sane_get_option_descriptor(handle, number);
        int value;
        auto status = sane_control_option(handle, number, SANE_Action.SANE_ACTION_GET_VALUE, &value, null);
        enforce(status == SANE_Status.SANE_STATUS_GOOD);
        return value;
    }

    @property void value(int v) {
        if(!settable())
            throw new Exception("Option is not settable");
        sane_get_option_descriptor(handle, number);
        auto status = sane_control_option(handle, number, SANE_Action.SANE_ACTION_SET_VALUE, &v, null);
        enforce(status == SANE_Status.SANE_STATUS_GOOD);
    }
}

unittest {
    import std.stdio;
    auto s = new Sane();
    s.init();
    auto devices = s.devices();
    writeln(devices[0]);
    writeln(devices[0].options[0]);
    assert(devices[0].options[3].value == 8);
    devices[0].options[3].value = 16;
    assert(devices[0].options[3].value == 16);
    assert(devices[0].options[3].settable);
    assert(devices[0].options[3].active);
    devices[0].readImage();
    assertThrown(devices[0].options[0].value = 5);
}
