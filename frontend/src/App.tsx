import React from "react";
import { BrowserRouter, Routes, Route, NavLink } from "react-router-dom";
import UploadPage from "./pages/UploadPage";
import SearchPage from "./pages/SearchPage";

export default function App() {
  return (
    <BrowserRouter>
      <nav>
        <NavLink to="/" className="brand">PDF Search</NavLink>
        <NavLink to="/" end className={({ isActive }) => isActive ? "active" : ""}>
          Upload
        </NavLink>
        <NavLink to="/search" className={({ isActive }) => isActive ? "active" : ""}>
          Search
        </NavLink>
      </nav>
      <Routes>
        <Route path="/" element={<UploadPage />} />
        <Route path="/search" element={<SearchPage />} />
      </Routes>
    </BrowserRouter>
  );
}
