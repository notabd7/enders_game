const std = @import("std");
const rl = @import("raylib");
const math = std.math;
const rlm = rl.math;
const rand = std.rand;
//represents a 2-d vector with cords x and y defaulted to 0,0
const Vector2 = rl.Vector2;

const THICKNESS = 1.5;
const SCALE = 30.0;
const SIZE = Vector2.init(800, 800);

const Ship = struct {
    position: Vector2,
    velocity: Vector2,
    rotation: f32,
    deathTime: f32 = 0.0,

    fn isDead(self: @This()) bool {
        return self.deathTime != 0.0;
    }
};

const AlienSize = enum {
    BIG,
    SMALL,

    fn collisionSize(self: @This()) f32 {
        return switch (self) {
            .BIG => SCALE * 0.8,
            .SMALL => SCALE * 0.5,
        };
    }

    fn directionChangeTime(self: @This()) f32 {
        return switch (self) {
            .BIG => 0.85,
            .SMALL => 0.35,
        };
    }

    fn shotTime(self: @This()) f32 {
        return switch (self) {
            .BIG => 1.25,
            .SMALL => 0.75,
        };
    }

    fn speed(self: @This()) f32 {
        return switch (self) {
            .BIG => 3,
            .SMALL => 6,
        };
    }
};

const Asteroid = struct {
    position: Vector2,
    velocity: Vector2,
    size: AsteroidSize,
    seed: u64,
    remove: bool = false,
};

const Particle = struct {
    position: Vector2,
    velocity: Vector2,
    ttl: f32,

    values: union(ParticleType) {
        LINE: struct {
            rotation: f32,
            length: f32,
        },
        DOT: struct {
            radius: f32,
        },
    },
};

const Projectile = struct {
    position: Vector2,
    velocity: Vector2,
    ttl: f32,
    spawn: f32,
    remove: bool = false,
};

const Alien = struct {
    position: Vector2,
    direction: Vector2,
    size: AlienSize,
    remove: bool = false,
    lastShot: f32 = 0,
    lastDirection: f32 = 0,
};

const ParticleType = enum {
    LINE,
    DOT,
};

//defining a struct to use for defining player position
const State = struct {
    ship: Ship,
    change: f32 = 0,
    current: f32 = 0,
    stageStart: f32 = 0,
    asteroids: std.ArrayList(Asteroid),
    asteroids_queue: std.ArrayList(Asteroid),
    particles: std.ArrayList(Particle),
    projectiles: std.ArrayList(Projectile),
    aliens: std.ArrayList(Alien),
    rand: rand.Random,
    lives: usize = 0,
    lastScore: usize = 0,
    score: usize = 0,
    reset: bool = false,
    lastBloop: usize = 0,
    bloop: usize = 0,
    frame: usize = 0,
};

// initializes state to type State
var state: State = undefined;

const Sound = struct {
    bloopLo: rl.Sound,
    bloopHi: rl.Sound,
    shoot: rl.Sound,
    thrust: rl.Sound,
    asteroid: rl.Sound,
    boom: rl.Sound,
};

var sound: Sound = undefined;

// a function that takes in the origin i.e 0,0(default val of vector2), a scale factor, and an array of coordinates, return nothing hence void
fn drawLines(origin: Vector2, scale: f32, rotation: f32, points: []const Vector2, connect: bool) void {
    // a transformer struct that has origin again 0,0 and scale factor tpo scale each point before drawing a line btw them
    const Transformer = struct {
        origin: Vector2,
        scale: f32,
        rotation: f32,
        //this is where the scaling followed by translation occurs
        //self: Refers to the current instance of the Transformer struct. In Zig, self: @This() refers to the instance of the struct from which the method was called.
        fn apply(self: @This(), p: Vector2) Vector2 {
            // vector2sclae multiplies cords of p by the scale, and vector2add adds this resulting vector to the origin (0,0)
            // i recommend drawing all of this on a graph on a piece of paper
            return rlm.vector2Add(
                rlm.vector2Scale(rlm.vector2Rotate(p, self.rotation), self.scale),
                self.origin,
            );
        }
    };

    // Initializes a Transformer instance with the provided origin and scale.
    const t = Transformer{
        .origin = origin,
        .scale = scale,
        .rotation = rotation,
    };

    //ngl for loops zig look cool
    //loop iterates over a range of integers 0 to points.len (not including points.len)
    // i is the iterator

    const bound = if (connect) points.len else (points.len - 1);
    for (0..bound) |i| {
        rl.drawLineEx(
            t.apply(points[i]),
            t.apply(points[(i + 1) % points.len]),
            THICKNESS,
            rl.Color.white,
        );
    }
}

fn drawNumber(n: usize, position: Vector2) !void {
    const NUMBER_LINES = [10][]const [2]f32{
        &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 } },
        &.{ .{ 0.5, 0 }, .{ 0.5, 1 } },
        &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 0, 0 }, .{ 1, 0 } },
        &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 0 }, .{ 0, 0 } },
        &.{ .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 1 }, .{ 1, 0 } },
        &.{ .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 0 }, .{ 0, 0 } },
        &.{ .{ 0, 1 }, .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.5 }, .{ 0, 0.5 } },
        &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 } },
        &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 0, 0 } },
        &.{ .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 } },
    };

    var position2 = position;

    var val = n;
    var digits: usize = 0;
    while (val >= 0) {
        digits += 1;
        val /= 10;
        if (val == 0) {
            break;
        }
    }

    //pos2.x += @as(f32, @floatFromInt(digits)) * SCALE;
    val = n;
    while (val >= 0) {
        var points = try std.BoundedArray(Vector2, 16).init(0);
        for (NUMBER_LINES[val % 10]) |p| {
            try points.append(Vector2.init(p[0] - 0.5, (1.0 - p[1]) - 0.5));
        }

        drawLines(position2, SCALE * 0.8, 0, points.slice(), false);
        position2.x -= SCALE;
        val /= 10;
        if (val == 0) {
            break;
        }
    }
}

const AsteroidSize = enum {
    BIG,
    MEDIUM,
    SMALL,

    fn score(self: @This()) usize {
        return switch (self) {
            .BIG => 20,
            .MEDIUM => 50,
            .SMALL => 100,
        };
    }

    fn size(self: @This()) f32 {
        return switch (self) {
            .BIG => SCALE * 3.0,
            .MEDIUM => SCALE * 1.4,
            .SMALL => SCALE * 0.8,
        };
    }

    fn collisionScale(self: @This()) f32 {
        return switch (self) {
            .BIG => 0.4,
            .MEDIUM => 0.65,
            .SMALL => 1.0,
        };
    }

    fn velocityScale(self: @This()) f32 {
        return switch (self) {
            .BIG => 0.75,
            .MEDIUM => 0.9,
            .SMALL => 1.5,
        };
    }
};

fn drawAsteroid(position: Vector2, size: AsteroidSize, seed: u64) !void {
    var prng = rand.Xoshiro256.init(seed);
    var random = prng.random();

    var points = try std.BoundedArray(Vector2, 16).init(0);
    const n = random.intRangeLessThan(i32, 8, 15);

    for (0..@intCast(n)) |i| {
        var radius = 0.3 + (0.2 * random.float(f32));
        if (random.float(f32) < 0.2) {
            radius -= 0.2;
        }

        const angle: f32 = (@as(f32, @floatFromInt(i)) * (math.tau / @as(f32, @floatFromInt(n)))) + (math.pi * 0.125 * random.float(f32));
        try points.append(
            rlm.vector2Scale(Vector2.init(math.cos(angle), math.sin(angle)), radius),
        );
    }

    drawLines(position, size.size(), 0.0, points.slice(), true);
}

fn splatLines(position: Vector2, count: usize) !void {
    for (0..count) |_| {
        const angle = math.tau * state.rand.float(f32);
        try state.particles.append(.{
            .position = rlm.vector2Add(
                position,
                Vector2.init(state.rand.float(f32) * 3, state.rand.float(f32) * 3),
            ),
            .velocity = rlm.vector2Scale(
                Vector2.init(math.cos(angle), math.sin(angle)),
                2.0 * state.rand.float(f32),
            ),
            .ttl = 3.0 + state.rand.float(f32),
            .values = .{
                .LINE = .{
                    .rotation = math.tau * state.rand.float(f32),
                    .length = SCALE * (0.6 + (0.4 * state.rand.float(f32))),
                },
            },
        });
    }
}

fn splatDots(position: Vector2, count: usize) !void {
    for (0..count) |_| {
        const angle = math.tau * state.rand.float(f32);
        try state.particles.append(.{
            .position = rlm.vector2Add(
                position,
                Vector2.init(state.rand.float(f32) * 3, state.rand.float(f32) * 3),
            ),
            .velocity = rlm.vector2Scale(
                Vector2.init(math.cos(angle), math.sin(angle)),
                2.0 + 4.0 * state.rand.float(f32),
            ),
            .ttl = 0.5 + (0.4 * state.rand.float(f32)),
            .values = .{
                .DOT = .{
                    .radius = SCALE * 0.025,
                },
            },
        });
    }
}

fn hitAsteroid(a: *Asteroid, impact: ?Vector2) !void {
    rl.playSound(sound.asteroid);

    state.score += a.size.score();
    a.remove = true;

    try splatDots(a.position, 10);

    if (a.size == .SMALL) {
        return;
    }

    for (0..2) |_| {
        const direction = rlm.vector2Normalize(a.velocity);
        const size: AsteroidSize = switch (a.size) {
            .BIG => .MEDIUM,
            .MEDIUM => .SMALL,
            else => unreachable,
        };

        try state.asteroids_queue.append(.{
            .position = a.position,
            .velocity = rlm.vector2Add(
                rlm.vector2Scale(
                    direction,
                    a.size.velocityScale() * 2.2 * state.rand.float(f32),
                ),
                if (impact) |i| rlm.vector2Scale(i, 0.7) else Vector2.init(0, 0),
            ),
            .size = size,
            .seed = state.rand.int(u64),
        });
    }
}

fn update() !void {
    if (state.reset) {
        state.reset = false;
        try resetGame();
    }

    if (!state.ship.isDead()) {
        // rotations / second
        const ROTATION_SPEED = 2;
        const SHIP_SPEED = 24;

        if (rl.isKeyDown(.key_a)) {
            state.ship.rotation -= state.change * math.tau * ROTATION_SPEED;
        }

        if (rl.isKeyDown(.key_d)) {
            state.ship.rotation += state.change * math.tau * ROTATION_SPEED;
        }

        const directionAngle = state.ship.rotation + (math.pi * 0.5);
        const shipDirection = Vector2.init(math.cos(directionAngle), math.sin(directionAngle));

        if (rl.isKeyDown(.key_w)) {
            state.ship.velocity = rlm.vector2Add(
                state.ship.velocity,
                rlm.vector2Scale(shipDirection, state.change * SHIP_SPEED),
            );

            if (state.frame % 2 == 0) {
                rl.playSound(sound.thrust);
            }
        }

        const DRAG = 0.019;
        state.ship.velocity = rlm.vector2Scale(state.ship.velocity, 1.0 - DRAG);
        state.ship.position = rlm.vector2Add(state.ship.position, state.ship.velocity);
        state.ship.position = Vector2.init(
            @mod(state.ship.position.x, SIZE.x),
            @mod(state.ship.position.y, SIZE.y),
        );

        if (rl.isKeyPressed(.key_space) or rl.isMouseButtonPressed(.mouse_button_left)) {
            try state.projectiles.append(.{
                .position = rlm.vector2Add(
                    state.ship.position,
                    rlm.vector2Scale(shipDirection, SCALE * 0.55),
                ),
                .velocity = rlm.vector2Scale(shipDirection, 10.0),
                .ttl = 2.0,
                .spawn = state.current,
            });
            rl.playSound(sound.shoot);

            state.ship.velocity = rlm.vector2Add(state.ship.velocity, rlm.vector2Scale(shipDirection, -0.5));
        }

        // check for projectile v. ship collision
        for (state.projectiles.items) |*p| {
            if (!p.remove and (state.current - p.spawn) > 0.15 and rlm.vector2Distance(state.ship.position, p.position) < (SCALE * 0.7)) {
                p.remove = true;
                state.ship.deathTime = state.current;
            }
        }
    }

    // add asteroids from queue
    for (state.asteroids_queue.items) |a| {
        try state.asteroids.append(a);
    }
    try state.asteroids_queue.resize(0);

    {
        var i: usize = 0;
        while (i < state.asteroids.items.len) {
            var a = &state.asteroids.items[i];
            a.position = rlm.vector2Add(a.position, a.velocity);
            a.position = Vector2.init(
                @mod(a.position.x, SIZE.x),
                @mod(a.position.y, SIZE.y),
            );

            // check for ship v. asteroid collision
            if (!state.ship.isDead() and rlm.vector2Distance(a.position, state.ship.position) < a.size.size() * a.size.collisionScale()) {
                state.ship.deathTime = state.current;
                try hitAsteroid(a, rlm.vector2Normalize(state.ship.velocity));
            }

            // check for alien v. asteroid collision
            for (state.aliens.items) |*l| {
                if (!l.remove and rlm.vector2Distance(a.position, l.position) < a.size.size() * a.size.collisionScale()) {
                    l.remove = true;
                    try hitAsteroid(a, rlm.vector2Normalize(state.ship.velocity));
                }
            }

            // check for projectile v. asteroid collision
            for (state.projectiles.items) |*p| {
                if (!p.remove and rlm.vector2Distance(a.position, p.position) < a.size.size() * a.size.collisionScale()) {
                    p.remove = true;
                    try hitAsteroid(a, rlm.vector2Normalize(p.velocity));
                }
            }

            if (a.remove) {
                _ = state.asteroids.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    {
        var i: usize = 0;
        while (i < state.particles.items.len) {
            var p = &state.particles.items[i];
            p.position = rlm.vector2Add(p.position, p.velocity);
            p.position = Vector2.init(
                @mod(p.position.x, SIZE.x),
                @mod(p.position.y, SIZE.y),
            );

            if (p.ttl > state.change) {
                p.ttl -= state.change;
                i += 1;
            } else {
                _ = state.particles.swapRemove(i);
            }
        }
    }

    {
        var i: usize = 0;
        while (i < state.projectiles.items.len) {
            var p = &state.projectiles.items[i];
            p.position = rlm.vector2Add(p.position, p.velocity);
            p.position = Vector2.init(
                @mod(p.position.x, SIZE.x),
                @mod(p.position.y, SIZE.y),
            );

            if (!p.remove and p.ttl > state.change) {
                p.ttl -= state.change;
                i += 1;
            } else {
                _ = state.projectiles.swapRemove(i);
            }
        }
    }

    {
        var i: usize = 0;
        while (i < state.aliens.items.len) {
            var a = &state.aliens.items[i];

            // check for projectile v. alien collision
            for (state.projectiles.items) |*p| {
                if (!p.remove and (state.current - p.spawn) > 0.15 and rlm.vector2Distance(a.position, p.position) < a.size.collisionSize()) {
                    p.remove = true;
                    a.remove = true;
                }
            }

            // check alien v. ship
            if (!a.remove and rlm.vector2Distance(a.position, state.ship.position) < a.size.collisionSize()) {
                a.remove = true;
                state.ship.deathTime = state.current;
            }

            if (!a.remove) {
                if ((state.current - a.lastDirection) > a.size.directionChangeTime()) {
                    a.lastDirection = state.current;
                    const angle = math.tau * state.rand.float(f32);
                    a.direction = Vector2.init(math.cos(angle), math.sin(angle));
                }

                a.position = rlm.vector2Add(a.position, rlm.vector2Scale(a.direction, a.size.speed()));
                a.position = Vector2.init(
                    @mod(a.position.x, SIZE.x),
                    @mod(a.position.y, SIZE.y),
                );

                if ((state.current - a.lastShot) > a.size.shotTime()) {
                    a.lastShot = state.current;
                    const direction = rlm.vector2Normalize(rlm.vector2Subtract(state.ship.position, a.position));
                    try state.projectiles.append(.{
                        .position = rlm.vector2Add(
                            a.position,
                            rlm.vector2Scale(direction, SCALE * 0.55),
                        ),
                        .velocity = rlm.vector2Scale(direction, 6.0),
                        .ttl = 2.0,
                        .spawn = state.current,
                    });
                    rl.playSound(sound.shoot);
                }
            }

            if (a.remove) {
                rl.playSound(sound.asteroid);
                try splatDots(a.position, 15);
                try splatLines(a.position, 4);
                _ = state.aliens.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    if (state.ship.deathTime == state.current) {
        rl.playSound(sound.boom);
        try splatDots(state.ship.position, 20);
        try splatLines(state.ship.position, 5);
    }

    if (state.ship.isDead() and (state.current - state.ship.deathTime) > 3.0) {
        try resetStage();
    }

    const bloopIntensity = @min(@as(usize, @intFromFloat(state.current - state.stageStart)) / 15, 3);

    var bloopMod: usize = 60;
    for (0..bloopIntensity) |_| {
        bloopMod /= 2;
    }

    if (state.frame % bloopMod == 0) {
        state.bloop += 1;
    }

    if (!state.ship.isDead() and state.bloop != state.lastBloop) {
        rl.playSound(if (state.bloop % 2 == 1) sound.bloopHi else sound.bloopLo);
    }
    state.lastBloop = state.bloop;

    if (state.asteroids.items.len == 0 and state.aliens.items.len == 0) {
        try resetAsteroids();
    }

    if ((state.lastScore / 5000) != (state.score / 5000)) {
        try state.aliens.append(.{
            .position = Vector2.init(
                if (state.rand.boolean()) 0 else SIZE.x - SCALE,
                state.rand.float(f32) * SIZE.y,
            ),
            .direction = Vector2.init(0, 0),
            .size = .BIG,
        });
    }

    if ((state.lastScore / 8000) != (state.score / 8000)) {
        try state.aliens.append(.{
            .position = Vector2.init(
                if (state.rand.boolean()) 0 else SIZE.x - SCALE,
                state.rand.float(f32) * SIZE.y,
            ),
            .direction = Vector2.init(0, 0),
            .size = .SMALL,
        });
    }

    state.lastScore = state.score;
}

fn drawAlien(position: Vector2, size: AlienSize) void {
    const scale: f32 = switch (size) {
        .BIG => 1.0,
        .SMALL => 0.5,
    };

    drawLines(position, SCALE * scale, 0, &.{
        Vector2.init(-0.5, 0.0),
        Vector2.init(-0.3, 0.3),
        Vector2.init(0.3, 0.3),
        Vector2.init(0.5, 0.0),
        Vector2.init(0.3, -0.3),
        Vector2.init(-0.3, -0.3),
        Vector2.init(-0.5, 0.0),
        Vector2.init(0.5, 0.0),
    }, false);

    drawLines(position, SCALE * scale, 0, &.{
        Vector2.init(-0.2, -0.3),
        Vector2.init(-0.1, -0.5),
        Vector2.init(0.1, -0.5),
        Vector2.init(0.2, -0.3),
    }, false);
}

const SHIP_LINES = [_]Vector2{
    Vector2.init(-0.4, -0.5),
    Vector2.init(0.0, 0.5),
    Vector2.init(0.4, -0.5),
    Vector2.init(0.3, -0.4),
    Vector2.init(-0.3, -0.4),
};

fn render() !void {

    // draw remaining lives
    for (0..state.lives) |i| {
        drawLines(
            Vector2.init(SCALE + (@as(f32, @floatFromInt(i)) * SCALE), SCALE),
            SCALE,
            -math.pi,
            &SHIP_LINES,
            true,
        );
    }

    // draw score
    try drawNumber(state.score, Vector2.init(SIZE.x - SCALE, SCALE));

    if (!state.ship.isDead()) {
        drawLines(
            state.ship.position,
            SCALE,
            state.ship.rotation,
            &SHIP_LINES,
            true,
        );

        if (rl.isKeyDown(.key_w) and @mod(@as(i32, @intFromFloat(state.current * 30)), 2) == 0) {
            drawLines(
                state.ship.position,
                SCALE,
                state.ship.rotation,
                &.{
                    Vector2.init(-0.3, -0.4),
                    Vector2.init(0.0, -0.8),
                    Vector2.init(0.3, -0.4),
                },
                true,
            );
        }
    }

    for (state.asteroids.items) |a| {
        try drawAsteroid(a.position, a.size, a.seed);
    }

    for (state.aliens.items) |a| {
        drawAlien(a.position, a.size);
    }

    for (state.particles.items) |p| {
        switch (p.values) {
            .LINE => |line| {
                drawLines(
                    p.position,
                    line.length,
                    line.rotation,
                    &.{
                        Vector2.init(-0.5, 0),
                        Vector2.init(0.5, 0),
                    },
                    true,
                );
            },
            .DOT => |dot| {
                rl.drawCircleV(p.position, dot.radius, rl.Color.white);
            },
        }
    }

    for (state.projectiles.items) |p| {
        rl.drawCircleV(p.position, @max(SCALE * 0.05, 1), rl.Color.white);
    }
}

fn resetAsteroids() !void {
    try state.asteroids.resize(0);

    for (0..(30 + state.score / 1500)) |_| {
        const angle = math.tau * state.rand.float(f32);
        const size = state.rand.enumValue(AsteroidSize);
        try state.asteroids_queue.append(.{
            .position = Vector2.init(
                state.rand.float(f32) * SIZE.x,
                state.rand.float(f32) * SIZE.y,
            ),
            .velocity = rlm.vector2Scale(
                Vector2.init(math.cos(angle), math.sin(angle)),
                size.velocityScale() * 3.0 * state.rand.float(f32),
            ),
            .size = size,
            .seed = state.rand.int(u64),
        });
    }

    state.stageStart = state.current;
}

fn resetGame() !void {
    state.lives = 3;
    state.score = 0;

    try resetStage();
    try resetAsteroids();
}

// reset after losing a life
fn resetStage() !void {
    if (state.ship.isDead()) {
        if (state.lives == 0) {
            state.reset = true;
        } else {
            state.lives -= 1;
        }
    }

    state.ship.deathTime = 0.0;
    state.ship = .{
        .position = rlm.vector2Scale(SIZE, 0.5),
        .velocity = Vector2.init(0, 0),
        .rotation = 0.0,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    rl.initWindow(SIZE.x, SIZE.y, "ENDER's GAME");
    rl.setWindowPosition(100, 100);
    rl.setTargetFPS(60);

    rl.initAudioDevice();
    // rl.setMasterVolume(0.8);
    defer rl.closeAudioDevice();

    var prng = rand.Xoshiro256.init(@bitCast(std.time.timestamp()));

    state = .{
        .ship = .{ .position = rlm.vector2Scale(SIZE, 0.5), .velocity = Vector2.init(0, 0), .rotation = 0.0 },
        .asteroids = std.ArrayList(Asteroid).init(allocator),
        .asteroids_queue = std.ArrayList(Asteroid).init(allocator),
        .particles = std.ArrayList(Particle).init(allocator),
        .projectiles = std.ArrayList(Projectile).init(allocator),
        .aliens = std.ArrayList(Alien).init(allocator),
        .rand = prng.random(),
    };

    defer state.asteroids.deinit();
    defer state.asteroids_queue.deinit();
    defer state.particles.deinit();
    defer state.projectiles.deinit();
    defer state.aliens.deinit();

    sound = .{
        .bloopLo = rl.loadSound("bloop_lo.wav"),
        .bloopHi = rl.loadSound("bloop_hi.wav"),
        .shoot = rl.loadSound("shoot.wav"),
        .thrust = rl.loadSound("thrust.wav"),
        .asteroid = rl.loadSound("asteroid.wav"),
        .boom = rl.loadSound("explode.wav"),
    };

    try resetGame();

    while (!rl.windowShouldClose()) {
        state.change = rl.getFrameTime();
        state.current += state.change;

        try update();

        rl.beginDrawing();
        defer rl.endDrawing(); // {
        //                           }   still learn how defer statements work
        //                          rl.endDrawing()
        rl.clearBackground(rl.Color.black);
        // //draw a line
        // const a = rl.Vector2.init(10, 10);
        // const b = rl.Vector2.init(100, 100);
        try render();

        state.frame += 1;
    }
}
