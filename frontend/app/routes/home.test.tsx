import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it, vi } from "vitest";
import Home from "./home";

vi.mock("../lib/auth", () => ({
  useAuth: () => ({ user: null, loading: false, logout: vi.fn(), refresh: vi.fn() }),
}));

describe("Home", () => {
  it("renders the heading and sign-in buttons", () => {
    render(
      <MemoryRouter>
        <Home />
      </MemoryRouter>,
    );

    expect(screen.getByText("It works!")).toBeInTheDocument();
    expect(screen.getByText("Sign in with Google")).toBeInTheDocument();
    expect(screen.getByText("Sign in with Apple")).toBeInTheDocument();
  });
});
