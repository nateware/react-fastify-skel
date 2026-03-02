import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Welcome } from "./welcome";

describe("Welcome", () => {
  it("renders the welcome component", () => {
    render(<Welcome />);
    expect(screen.getByText("What's next?")).toBeInTheDocument();
  });

  it("renders navigation links", () => {
    render(<Welcome />);
    expect(screen.getByText("React Router Docs")).toBeInTheDocument();
    expect(screen.getByText("Join Discord")).toBeInTheDocument();
  });
});
