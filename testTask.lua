--- 模块功能：testTask
-- @module test
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.02.17
function taskb(v1, v2)
    local count = 2
    print("taskb start", v1, v2)
    while true do
        print("taskb delay", count)
        result, data = sys.waitUntil("SIM_IND", 5000)
        if result then
            print('receive SIM_IND')
        else
            print('wait SIM_IND timeout')
        end
        count = count + 2
    end
end

function taskc(v1, v2)
    local count = 2
    print("taskc start", v1, v2)
    while true do
        print("taskc delay", count)
        sys.wait(2000)
        count = count + 2
    end
end

function taskd(v1, v2)
    local count = 2
    print("taskd start", v1, v2)
    while true do
        print("taskd delay", count)
        sys.wait(3000)
        count = count + 2
    end
end

function taske(v1, v2)
    local count = 2
    print("taske start", v1, v2)
    while true do
        print("taske delay", count)
        sys.wait(4000)
        count = count + 2
    end
end

function taskf(v1, v2)
    local count = 2
    print("taskf start", v1, v2)
    while true do
        print("taskf delay", count)
        sys.wait(5000)
        count = count + 2
    end
end

function taskg(v1, v2)
    local count = 2
    print("taskg start", v1, v2)
    while true do
        print("taskg delay", count)
        sys.wait(6000)
        count = count + 2
    end
end

function taskh(v1, v2)
    local count = 2
    print("taskh start", v1, v2)
    while true do
        print("taskh delay", count)
        sys.wait(7000)
        count = count + 2
    end
end

function taski(v1, v2)
    local count = 2
    print("taski start", v1, v2)
    while true do
        print("taski delay", count)
        sys.wait(8000)
        count = count + 2
    end
end

function taskj(v1, v2)
    local count = 2
    print("taskj start", v1, v2)
    while true do
        print("taskj delay", count)
        sys.wait(9000)
        count = count + 2
    end
end

function taskk(v1, v2)
    local count = 2
    print("taskk start", v1, v2)
    while true do
        print("taskk delay", count)
        sys.wait(10000)
        count = count + 2
    end
end

function taskl(v1, v2)
    local count = 2
    print("taskl start", v1, v2)
    while true do
        print("taskl delay", count)
        sys.wait(11000)
        count = count + 2
    end
end

function taskm(v1, v2)
    local count = 2
    print("taskm start", v1, v2)
    while true do
        print("taskm delay", count)
        sys.wait(12000)
        count = count + 2
    end
end

function taskn(v1, v2)
    local count = 2
    print("taskn start", v1, v2)
    while true do
        print("taskn delay", count)
        sys.wait(13000)
        count = count + 2
    end
end

--
sys.taskInit(taskb, "b", "c")
--sys.taskInit(taskc, "c", "c")
--sys.taskInit(taskd, "d", "c")
--sys.taskInit(taske, "e", "c")
--sys.taskInit(taskf, "f", "c")
--sys.taskInit(taskg, "g", "c")
--sys.taskInit(taskh, "h", "c")
--sys.taskInit(taski, "i", "c")
--sys.taskInit(taskj, "j", "c")
--sys.taskInit(taskk, "k", "c")
--sys.taskInit(taskl, "l", "c")
--sys.taskInit(taskm, "m", "c")
--sys.taskInit(taskn, "n", "c")
